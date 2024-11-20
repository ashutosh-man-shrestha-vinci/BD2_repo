DROP SCHEMA gestion_evenements CASCADE;
CREATE SCHEMA gestion_evenements;
CREATE TABLE gestion_evenements.salles(
	id_salle SERIAL PRIMARY KEY,
	nom VARCHAR(50) NOT NULL CHECK (trim(nom) <> ''),
	ville VARCHAR(30) NOT NULL CHECK (trim(ville) <> ''),
	capacite INTEGER NOT NULL CHECK (capacite  > 0)
);

CREATE TABLE gestion_evenements.festivals (
	id_festival SERIAL PRIMARY KEY ,
	nom VARCHAR(100) NOT NULL CHECK (trim(nom) <> '')
);

CREATE TABLE gestion_evenements.evenements (
    salle            INTEGER     NOT NULL,
    date_evenement   DATE        NOT NULL,

    nom                 VARCHAR(50)    NOT NULL CHECK ( nom != '' ),
    prix                INTEGER        NOT NULL CHECK ( prix > 0 ),
    nb_places_restantes INTEGER        NOT NULL CHECK ( nb_places_restantes > 0 ),
    festival            INTEGER        NOT NULL,

    FOREIGN KEY (salle) REFERENCES gestion_evenements.salles(id_salle),
    FOREIGN KEY (festival) REFERENCES gestion_evenements.festivals(id_festival),
    PRIMARY KEY (salle, date_evenement)
);

CREATE TABLE gestion_evenements.artistes(
	id_artiste SERIAL PRIMARY KEY,
	nom VARCHAR(100) NOT NULL CHECK (trim(nom) <> ''),
	nationalite CHAR(3) NULL CHECK (trim(nationalite) SIMILAR TO '[A-Z]{3}')
);

CREATE TABLE gestion_evenements.concerts(
	artiste INTEGER NOT NULL REFERENCES gestion_evenements.artistes(id_artiste),
	salle INTEGER NOT NULL,
	date_evenement DATE NOT NULL,
	heure_debut TIME NOT NULL,
	PRIMARY KEY(artiste,date_evenement),
	UNIQUE(salle,date_evenement,heure_debut),
	FOREIGN KEY (salle,date_evenement) REFERENCES gestion_evenements.evenements(salle,date_evenement)
);

CREATE TABLE gestion_evenements.clients (
	id_client SERIAL PRIMARY KEY,
	nom_utilisateur VARCHAR(25) NOT NULL UNIQUE CHECK (trim(nom_utilisateur) <> '' ),
	email VARCHAR(50) NOT NULL CHECK (email SIMILAR TO '%@([[:alnum:]]+[.-])*[[:alnum:]]+.[a-zA-Z]{2,4}' AND trim(email) NOT LIKE '@%'),
	mot_de_passe CHAR(60) NOT NULL
);

CREATE TABLE gestion_evenements.reservations(
	salle INTEGER NOT NULL,
	date_evenement DATE NOT NULL,
	num_reservation INTEGER NOT NULL, --pas de check car sera géré automatiquement
	nb_tickets INTEGER CHECK (nb_tickets BETWEEN 1 AND 4),
	client INTEGER NOT NULL REFERENCES gestion_evenements.clients(id_client),
	PRIMARY KEY(salle,date_evenement,num_reservation),
	FOREIGN KEY (salle,date_evenement) REFERENCES gestion_evenements.evenements(salle,date_evenement)
);


--ajout d'une salle .x
CREATE OR REPLACE FUNCTION gestion_evenements.ajouter_salle(_nom VARCHAR(50),
_ville VARCHAR(30),_capacite INTEGER) RETURNS INTEGER AS $$
DECLARE
_id_salle INTEGER;
BEGIN
INSERT INTO gestion_evenements.salles VALUES(DEFAULT, _nom,_ville, _capacite)
RETURNING id_salle INTO _id_salle;
RETURN _id_salle;
END
$$LANGUAGE plpgsql;
SELECT gestion_evenements.ajouter_salle('forest national', 'bruxelles', 5000);

--ajout d'un festival
CREATE OR REPLACE FUNCTION gestion_evenements.ajouter_festival(_nom VARCHAR(50) )RETURNS INTEGER AS $$
DECLARE
_id_festival INTEGER;
BEGIN
INSERT INTO gestion_evenements.festivals VALUES(DEFAULT, _nom)
RETURNING _id_festival INTO _id_festival;
RETURN _id_festival;
END
$$LANGUAGE plpgsql;
SELECT gestion_evenements.ajouter_festival('Festival De Printemps');

--ajout d'un artiste
CREATE OR REPLACE FUNCTION gestion_evenements.ajouter_artiste(_nom VARCHAR(50) , _nationalite CHAR(3) )RETURNS INTEGER AS $$
DECLARE
_id_artiste INTEGER;
BEGIN
INSERT INTO gestion_evenements.artistes VALUES(DEFAULT, _nom ,_nationalite)
RETURNING _id_artiste INTO _id_artiste;
RETURN _id_artiste;
END
$$LANGUAGE plpgsql;
SELECT gestion_evenements.ajouter_artiste('Michael Jackson','BEL');
SELECT * FROM gestion_evenements.artistes;

--ajout client
CREATE OR REPLACE FUNCTION gestion_evenements.ajouter_client(_nom_utilisateur VARCHAR(50),_email VARCHAR(50),_mot_de_passe VARCHAR(60))RETURNS INTEGER AS $$
DECLARE
_id_client INTEGER;
BEGIN
INSERT INTO gestion_evenements.clients VALUES(DEFAULT , _nom_utilisateur ,_email ,_mot_de_passe )
RETURNING _id_client INTO _id_client;
RETURN _id_client;
END
$$LANGUAGE plpgsql;
SELECT gestion_evenements.ajouter_client('Michael Jackson','Michael.Jackson@gmail.com','123');
SELECT * FROM gestion_evenements.clients;

--semaine 7


--ajout d'un évenements + lancer des exceptions.
-- procédure d'ajout d'un événement
CREATE OR REPLACE FUNCTION gestion_evenements.ajouter_evenement(
    _id_salle INTEGER,
    _date_evenement DATE,
    _nom VARCHAR(100),
    _prix NUMERIC(8,2),
    _id_festival INTEGER
) RETURNS VOID AS $$
BEGIN
    IF (_date_evenement <= CURRENT_DATE) THEN
        RAISE EXCEPTION 'La date d''un événement ajouté doit être ultérieure à la date actuelle';
    END IF;

    INSERT INTO gestion_evenements.evenements(
        salle, date_evenement, nom, prix, festival, nb_places_restantes
    ) VALUES (
        _id_salle, _date_evenement, _nom, _prix, _id_festival,
        (SELECT s.capacite FROM gestion_evenements.salles s WHERE s.id_salle = _id_salle)
    );
END;
$$ LANGUAGE plpgsql;
--ajout d'une reservation
    CREATE OR REPLACE FUNCTION gestion_evenements.ajouter_une_reservation(
    _salle INTEGER,
    _date_evenement DATE,
    _num_reservation INTEGER,
    _nb_tickets INTEGER,
    _client INTEGER
) RETURNS INTEGER AS $$
DECLARE
    nb_places_restantes INTEGER;
    evenement_existe BOOLEAN;
    client_a_reservation BOOLEAN;
BEGIN
    -- Vérifier si la date de l'événement est passée
    IF (_date_evenement <= CURRENT_DATE) THEN
        RAISE EXCEPTION 'La date d''un événement ajouté doit être ultérieure à la date actuelle';
    END IF;

    -- Vérifier si l'événement a un concert
    SELECT COUNT(*) > 0 INTO evenement_existe
    FROM gestion_evenements.evenements
    WHERE salle = _salle AND date_evenement = _date_evenement;

    IF NOT evenement_existe THEN
        RAISE EXCEPTION 'L''événement n''a pas de concert prévu';
    END IF;

    -- Vérifier si le client réserve trop de places
    SELECT _nb_tickets INTO nb_places_restantes
    FROM gestion_evenements.evenements
    WHERE salle = _salle AND date_evenement = _date_evenement;

    IF (_nb_tickets > nb_places_restantes) THEN
        RAISE EXCEPTION 'Le client réserve trop de places pour l''événement';
    END IF;

    -- Vérifier si le client a déjà une réservation pour un autre événement à la même date
    SELECT COUNT(*) > 0 INTO client_a_reservation
    FROM gestion_evenements.reservations
    WHERE client = _client AND date_evenement = _date_evenement;

    IF client_a_reservation THEN
        RAISE EXCEPTION 'Le client a déjà une réservation pour un autre événement à la même date';
    END IF;

    -- Insérer la nouvelle réservation
    INSERT INTO gestion_evenements.reservations (
        salle, date_evenement, num_reservation, nb_tickets, client
    ) VALUES (
        _salle, _date_evenement, _num_reservation, _nb_tickets, _client
    );

    -- Mettre à jour le nombre de places restantes de l'événement
    UPDATE gestion_evenements.evenements
    SET nb_places_restantes = evenements.nb_places_restantes - _nb_tickets
    WHERE salle = _salle AND date_evenement = _date_evenement;


END;
$$ LANGUAGE plpgsql;

-- Exemples d'utilisation
SELECT gestion_evenements.ajouter_salle('forest national', 'Bruxelles', 3000);
SELECT gestion_evenements.ajouter_evenement(1, '2025-05-04', 'concert de Beyoncé', 200, 1);
SELECT gestion_evenements.ajouter_une_reservation(1, '2025-05-04', 12345, 2, 100);
--******************TEST*****************-
SELECT * FROM gestion_evenements.evenements;
SELECT * FROM gestion_evenements.salles;
SELECT * FROM gestion_evenements.artistes;
SELECT * FROM gestion_evenements.clients;
SELECT * FROM gestion_evenements.artistes;




