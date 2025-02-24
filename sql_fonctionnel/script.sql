DROP SCHEMA IF EXISTS gestion_evenements CASCADE;

CREATE SCHEMA gestion_evenements;

CREATE TABLE gestion_evenements.salles(
    id_salle    SERIAL      PRIMARY KEY,
    nom         VARCHAR(50) NOT NULL CHECK (trim(nom) <> ''),
    ville       VARCHAR(30) NOT NULL CHECK (trim(ville) <> ''),
    capacite    INTEGER NOT NULL CHECK (capacite > 0)
);

CREATE TABLE gestion_evenements.festivals (
    id_festival SERIAL          PRIMARY KEY,
    nom         VARCHAR(100)    NOT NULL CHECK (trim(nom) <> '')
);

CREATE TABLE gestion_evenements.evenements (
    salle               INTEGER         NOT NULL REFERENCES gestion_evenements.salles(id_salle),
    date_evenement      DATE            NOT NULL,
    nom                 VARCHAR(100)    NOT NULL CHECK (trim(nom) <> ''),
    prix                MONEY           NOT NULL CHECK (prix >= 0 :: MONEY),
    nb_places_restantes INTEGER         NOT NULL CHECK (nb_places_restantes >= 0),
    festival            INTEGER         REFERENCES gestion_evenements.festivals(id_festival),
    PRIMARY KEY (salle,date_evenement)
);

CREATE TABLE gestion_evenements.artistes(
    id_artiste  SERIAL          PRIMARY KEY,
    nom         VARCHAR(100)    NOT NULL CHECK (trim(nom) <> ''),
    nationalite CHAR(3)         NULL CHECK (trim(nationalite) SIMILAR TO '[A-Z]{3}')
);

CREATE TABLE gestion_evenements.concerts(
    artiste         INTEGER NOT NULL REFERENCES gestion_evenements.artistes(id_artiste),
    salle           INTEGER NOT NULL,
    date_evenement  DATE    NOT NULL,
    heure_debut     TIME    NOT NULL,

    PRIMARY KEY(artiste,date_evenement),
    UNIQUE(salle,date_evenement,heure_debut),
    FOREIGN KEY (salle,date_evenement) REFERENCES gestion_evenements.evenements(salle,date_evenement)
);

CREATE TABLE gestion_evenements.clients (
    id_client       SERIAL      PRIMARY KEY,
    nom_utilisateur VARCHAR(25) NOT NULL UNIQUE CHECK (trim(nom_utilisateur) <> '' ),
    email           VARCHAR(50) NOT NULL CHECK (email SIMILAR TO '%@([[:alnum:]]+[.-])*[[:alnum:]]+.[a-zA-Z]{2,4}' AND trim(email) NOT LIKE '@%'),
    mot_de_passe    CHAR(60)    NOT NULL
);

CREATE TABLE gestion_evenements.reservations(
    salle           INTEGER NOT NULL,
    date_evenement  DATE    NOT NULL,
    num_reservation INTEGER NOT NULL, --pas de check car sera géré automatiquement
    nb_tickets      INTEGER CHECK (nb_tickets BETWEEN 1 AND 4),
    client          INTEGER NOT NULL REFERENCES gestion_evenements.clients(id_client),

    PRIMARY KEY(salle,date_evenement,num_reservation),
    FOREIGN KEY (salle,date_evenement) REFERENCES gestion_evenements.evenements(salle,date_evenement)
);

-- ajout salle
CREATE OR REPLACE FUNCTION gestion_evenements.ajouterSalle(_nom VARCHAR(50), _ville VARCHAR(30), _capacite INTEGER) RETURNS INTEGER AS $$
DECLARE
    toReturn INTEGER;
BEGIN
    INSERT INTO gestion_evenements.salles(nom, ville, capacite) VALUES (_nom, _ville, _capacite)
    RETURNING id_salle INTO toReturn;
    RETURN toReturn;
END;
$$ LANGUAGE plpgsql;

-- ajout festival
CREATE OR REPLACE FUNCTION gestion_evenements.ajouterFestival(_nom VARCHAR(100)) RETURNS INTEGER AS $$
DECLARE
    toReturn INTEGER;
BEGIN
    INSERT INTO gestion_evenements.festivals(nom) VALUES (_nom)
    RETURNING id_festival INTO toReturn;
    RETURN toReturn;
END;
$$ LANGUAGE plpgsql;

-- ajout artiste
CREATE OR REPLACE FUNCTION gestion_evenements.ajouterArtiste(_nom VARCHAR(100), _nationalite CHAR(3)) RETURNS INTEGER AS $$
DECLARE
    toReturn INTEGER;
BEGIN
    INSERT INTO gestion_evenements.artistes(nom, nationalite) VALUES (_nom, _nationalite)
    RETURNING id_artiste INTO toReturn;
    RETURN toReturn;
END;
$$ LANGUAGE plpgsql;

-- ajout client
CREATE OR REPLACE FUNCTION gestion_evenements.ajouterClient(_nom_utilisateur VARCHAR(25), _email VARCHAR(50), _mot_de_passe VARCHAR(60))
    RETURNS INTEGER AS $$
DECLARE
    toReturn INTEGER;
BEGIN
    INSERT INTO gestion_evenements.clients(nom_utilisateur, email, mot_de_passe) VALUES (_nom_utilisateur, _email, _mot_de_passe)
    RETURNING id_client INTO toReturn;
    RETURN toReturn;
END
$$ LANGUAGE plpgsql;

-- ajout évènement
CREATE OR REPLACE FUNCTION gestion_evenements.ajouterEvenement(_salle INTEGER, _date_evenement DATE, _nom VARCHAR(100), _prix MONEY, _festival INTEGER) RETURNS VOID AS $$
DECLARE
    _nb_places_restantes INTEGER;
BEGIN
    INSERT INTO gestion_evenements.evenements(salle, date_evenement, nom, prix, festival, nb_places_restantes)
    VALUES (_salle, _date_evenement, _nom, _prix, _festival, _nb_places_restantes);
END
$$ LANGUAGE plpgsql;

-- trigger ajout évènement
CREATE OR REPLACE FUNCTION gestion_evenements.ajouterEvenementTrigger() RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.date_evenement <= CURRENT_DATE) THEN
        RAISE EXCEPTION 'la date de l''événement ajoutée est antérieure à la date actuelle';
    END IF;
    NEW.nb_places_restantes = (SELECT s.capacite FROM gestion_evenements.salles s WHERE s.id_salle = NEW.salle);
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER ajouterEvenementTrigger BEFORE INSERT ON gestion_evenements.evenements
FOR EACH ROW EXECUTE PROCEDURE gestion_evenements.ajouterEvenementTrigger();

-- ajout concert
CREATE OR REPLACE FUNCTION gestion_evenements.ajouterConcert(_artiste INTEGER, _date_evenement DATE, _heure_debut TIME, _salle INTEGER)
    RETURNS VOID AS $$
BEGIN
    INSERT INTO gestion_evenements.concerts(artiste, date_evenement, heure_debut, salle)
    VALUES (_artiste, _date_evenement, _heure_debut, _salle);
END
$$ LANGUAGE plpgsql;
-- trigger concert
CREATE OR REPLACE FUNCTION gestion_evenements.ajouterConcertTrigger() RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.date_evenement < CURRENT_DATE) THEN
        RAISE EXCEPTION 'La date de l''événement ajoutée est antérieure à la date actuelle';
    END IF;

    IF (EXISTS(SELECT 1
               FROM gestion_evenements.concerts c, gestion_evenements.evenements e
               WHERE c.salle = e.salle
                 AND c.date_evenement = e.date_evenement
                 AND c.artiste = NEW.artiste
                 AND e.salle = NEW.salle
                 AND e.festival IS NOT NULL)) THEN
        RAISE EXCEPTION 'Un artiste ne peut pas avoir deux concerts pour le même festival';
    END IF;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER ajouterConcertTrigger BEFORE INSERT ON gestion_evenements.concerts
FOR EACH ROW EXECUTE PROCEDURE gestion_evenements.ajouterConcertTrigger();

-- ajout réservation
CREATE OR REPLACE FUNCTION gestion_evenements.AjouterReservation(_id_salle INTEGER ,_date_evenement DATE , _nb_tickets INTEGER, _id_client INTEGER ) RETURNS INTEGER AS $$
DECLARE toreturn INTEGER;
    BEGIN
    INSERT INTO gestion_evenements.reservations(salle, date_evenement, nb_tickets, client) VALUES (_id_salle,_date_evenement,_nb_tickets, _id_client)
    RETURNING reservations.num_reservation INTO toreturn;
    RETURN toreturn;
end;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION gestion_evenements.AjouterReservationTrigger() RETURNS TRIGGER AS $$
    DECLARE toReturn INTEGER;
            BEGIN
        IF(NEW.date_evenement<=CURRENT_date) THEN RAISE EXCEPTION 'La date de lévenement est déjà passé';
        END IF;
        IF(NOT EXISTS(SELECT * FROM gestion_evenements.concerts c WHERE c.date_evenement = NEW.date_evenement AND c.salle = NEW.salle)) THEN RAISE EXCEPTION 'Levenement na pas de concert';
        END IF;

        IF(NEW.nb_tickets + (SELECT COALESCE(sum(r.nb_tickets),0) FROM gestion_evenements.reservations
            r WHERE r.client = NEW.client
                AND r.salle = NEW.salle
                and r.date_evenement = NEW.date_evenement))>4 THEN RAISE EXCEPTION 'bite';
                END IF;

        IF(EXISTS(SELECT * FROM gestion_evenements.reservations r  WHERE r.date_evenement = NEW.date_evenement AND r.client = NEW.client AND r.salle != NEW.salle )) THEN RAISE EXCEPTION 'teub';
        END IF;

UPDATE gestion_evenements.evenements c SET nb_places_restantes = nb_places_restantes - NEW.nb_tickets WHERE c.date_evenement = NEW.date_evenement AND c.salle = NEW.salle;


        SELECT COUNT(*) +1 from gestion_evenements.reservations r WHERE r.date_evenement = NEW.date_evenement AND r.salle = NEW.salle into NEW.num_reservation;
        RETURN NEW;
    END

    $$ LANGUAGE plpgsql;

CREATE TRIGGER AJOUTERTRIGGER BEFORE INSERT ON gestion_evenements.reservations FOR EACH ROW EXECUTE PROCEDURE gestion_evenements.AjouterReservationTrigger();


--semaine 9
--Ajouter la procédure de réservation d’un certain nombre de places pour tous les événements
--d’un festival. Si une des réservations échoue, alors aucune réservation ne sera enregistrée.
--Tester la procédure.
--7. Ajouter les vues suivantes :
--- Ajouter la vue qui affiche les festivals futurs (festivals pour lesquels il existe au moins un
--événement dans le futur). Les festivals seront affichés avec leur nom, la date du premier
--événement, la date du dernier événement et la somme des prix des tickets de chaque
--événement le composant. Les festivals seront triés par la date du premier événement. Les
--festivals non finalisés (sans événements) ne sont pas affichés. Tester votre vue.
--- Ajouter la vue qui affiche ses réservations. Les réservations seront affichées avec le nom de
--l’événement, la date de l’événement, la salle, le numéro de réservation et le nombre de
--places réservées. Les réservations seront triées par la date de l’événement. Tester votre vue
--en affichant les réservations d’un client particulier (id=1 par exemple).

CREATE OR REPLACE FUNCTION gestion_evenements.ReserverFestival(_id_festival INTEGER , _id_client INTEGER, _nb_places INTEGER) RETURNS VOID AS $$
    DECLARE
    _evenement RECORD;

        BEGIN
        FOR _evenement IN
            SELECT e.date_evenement , e.salle FROM gestion_evenements.evenements e WHERE e.festival = _id_festival
        LOOP
            PERFORM gestion_evenements.ajouterReservation(_evenement.salle,_evenement.date_evenement,_nb_places,_id_client);
            end loop;
    end;
    $$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW gestion_evenements.festivalView AS
    SELECT f.id_festival , f.nom , MIN(e.date_evenement) , MAX(e.date_evenement) , SUM(e.prix)
           FROM gestion_evenements.festivals f , gestion_evenements.evenements e
    WHERE f.id_festival = e.festival
GROUP BY f.id_festival, f.nom
HAVING MAX(e.date_evenement)>=CURRENT_DATE
ORDER BY MIN(e.date_evenement);


CREATE OR REPLACE VIEW gestion_evenements.reservationsClients AS
SELECT e.nom, e.date_evenement, r.num_reservation, r.client, r.nb_tickets
FROM gestion_evenements.evenements e, gestion_evenements.reservations r, gestion_evenements.salles s
WHERE r.date_evenement = e.date_evenement
  AND r.salle = e.salle
  AND r.salle = s.id_salle;

SELECT * FROM gestion_evenements.reservationsClients;

--semaine10
--Ajouter une vue qui affiche tous les événements d’une salle particulière triés par date. Les
--événements seront affichés avec les informations suivantes : son nom, sa date, sa salle, ses artistes
--séparés par des + (ex : « Beyoncé + Eminem »), son prix et s’il est complet ou non. Tester votre vue
--en affichant les événements de la salle dont l’id est1.
--9. Ajouter la vue qui affiche les événements auxquels participe un artiste particulier triés par date.
--Les événements seront affichés avec les informations suivantes : son nom, sa date, sa salle, ses
--artistes séparés par des + (ex : « Beyoncé + Eminem »), son prix et s’il est complet ou non. Tester
--votre vue en affichant les événements de l’artiste dont l’id est 1 .
--10. Début Partie Java Client : Créer un programme qui se connecte à la base de données et qui affiche
--tous les festivals futurs.

CREATE OR REPLACE VIEW gestion_evenements.evenementsParSalle AS
SELECT e.nom AS "nom_event", e.date_evenement AS "date_event", s.id_salle AS "id_salle_event",
       s.nom AS "nom_salle_event", STRING_AGG(a.nom, ',') AS "artistes",
       e.prix, e.nb_places_restantes = 0 AS "complet"
FROM gestion_evenements.salles s, gestion_evenements.evenements e
    LEFT JOIN gestion_evenements.concerts co ON e.date_evenement = co.date_evenement AND e.salle = co.salle
    LEFT JOIN gestion_evenements.artistes a ON a.id_artiste = co.artiste
WHERE e.salle = s.id_salle
GROUP BY e.nom, e.date_evenement, s.id_salle, s.nom, e.prix, e.nb_places_restantes;


CREATE OR REPLACE VIEW gestion_evenements.evenementsParArtiste AS
SELECT e.nom AS "nom_event", e.date_evenement AS "date_event", s.id_salle AS "id_salle_event",
       s.nom AS "nom_salle_event", STRING_AGG(a.nom, ',') AS "artistes",
       e.prix, e.nb_places_restantes = 0 AS "complet", a.id_artiste
FROM gestion_evenements.salles s, gestion_evenements.evenements e
    LEFT JOIN gestion_evenements.concerts co ON e.date_evenement = co.date_evenement AND e.salle = co.salle
    LEFT JOIN gestion_evenements.artistes a ON a.id_artiste = co.artiste
WHERE e.salle = s.id_salle
GROUP BY e.nom, e.date_evenement, s.id_salle, s.nom, e.prix, e.nb_places_restantes, a.id_artiste;

/* TESTS */
SELECT gestion_evenements.ajouterSalle('Palais 12', 'Bruxelles', 15000);
SELECT gestion_evenements.ajouterSalle('La Madeleine', 'Bruxelles', 15000);
SELECT gestion_evenements.ajouterSalle('Cirque Royal', 'Bruxelles', 15000);
SELECT gestion_evenements.ajouterSalle('Sportpaleis Antwerpen', 'Anvers', 15000);

SELECT gestion_evenements.ajouterFestival('Les Ardentes');
SELECT gestion_evenements.ajouterFestival('Lolapalooza');
SELECT gestion_evenements.ajouterFestival('Afronation');

SELECT gestion_evenements.ajouterArtiste('Beyoncé', 'USA');

SELECT gestion_evenements.ajouterClient('user007', 'user007@live.be', '***********');
--SELECT gestion_evenements.ajouterClient('user007', 'user007@.be', '***ok********'); --Test: PK
SELECT gestion_evenements.ajouterClient('user1203', 'user007@live.be', '***********');
--SELECT gestion_evenements.ajouterEvenement(1, '2024-11-21', 'Evenement1', 600.00::MONEY, 1); --TEST KO: date passée
SELECT gestion_evenements.ajouterEvenement(1, '2025-05-20', 'Evenement1', 600.00::MONEY, 1);
SELECT gestion_evenements.ajouterEvenement(2, '2025-05-01', 'Evenement2', 10.00::MONEY, 2);
--SELECT gestion_evenements.ajouterEvenement(1, '2024-11-21', 'Evenement2', 600.00::MONEY, 1); --Test: PK
--SELECT gestion_evenements.ajouterEvenement(1, '2024-09-21', 'Evenement1', 600.00::MONEY, 1); --Test: date antérieure
SELECT gestion_evenements.ajouterConcert(1, '2025-05-20', '20:00', 1);
--SELECT gestion_evenements.ajouterConcert(1, '2025-05-20', '10:00', 1); --Test: tentative artiste 2 concerts au même festival

SELECT gestion_evenements.ajouterReservation(1, '2025-05-20', 2, 1);

SELECT * FROM gestion_evenements.evenementsParSalle WHERE id_salle_event=2;