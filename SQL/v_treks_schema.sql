-- compatibilités : Schéma de données 0.2.0 / PostgreSQL 12 / PostGIS 2.4.3 / unaccent 1.1 / Geotrek-admin 2.62.0 / Geotrek-rando 2.30.1-ux

-- CREATE EXTENSION IF NOT EXISTS unaccent;

DROP VIEW IF EXISTS v_treks_schema;

CREATE VIEW v_treks_schema AS
WITH
    selected_t AS (
        SELECT *
        FROM trekking_trek t
        WHERE t.published IS TRUE
    ),
    sources AS (
        SELECT string_agg(c_1."name", ',')::text AS liste, t_1.trek_id -- création d'une chaîne de caractère de toutes les sources de l'itinéraire
        FROM common_recordsource c_1, trekking_trek_source t_1
        WHERE t_1.recordsource_id = c_1.id
        GROUP BY t_1.trek_id
        ),
    handi AS (
        SELECT string_agg(a."name", ',') AS liste, a_s.trek_id
        FROM trekking_accessibility a
        JOIN trekking_trek_accessibilities a_s ON a.id = a_s.accessibility_id
        JOIN selected_t t ON  t.topo_object_id = a_s.trek_id
        GROUP BY a_s.trek_id
        ),
    themes AS (
        SELECT string_agg(c_1.LABEL, ',') AS liste, t_1.trek_id
        FROM common_theme c_1
        JOIN trekking_trek_themes t_1 ON  c_1.id = t_1.theme_id
        JOIN selected_t t ON  t.topo_object_id = t_1.trek_id
        GROUP BY t_1.trek_id
        ),
    medias AS (
        SELECT c_1.object_id, jsonb_agg((jsonb_build_object('type_media', f.type, 'url', c_1.attachment_file, 'titre', c_1.legende, 'auteur', c_1.auteur, 'licence', 'licence'))) AS liste
        FROM trekking_trek t
        JOIN common_attachment c_1 ON t.topo_object_id = c_1.object_id
        JOIN common_filetype f ON f.id = c_1.filetype_id
        GROUP BY c_1.object_id
        ),
    balisage AS (
        SELECT string_agg(net.network, ',') AS b, tnet.trek_id
        FROM trekking_treknetwork net
        JOIN trekking_trek_networks tnet ON tnet.treknetwork_id = net.id
        JOIN selected_t t ON t.topo_object_id = tnet.trek_id
        GROUP BY tnet.trek_id
        ),
    sol AS (
        SELECT string_agg(t_1."name", ',') AS liste, e.topo_object_id
        FROM land_physicaledge e
        JOIN land_physicaltype t_1 ON e.physical_type_id = t_1.id
        JOIN selected_t t ON t.topo_object_id =  e.topo_object_id
        GROUP BY e.topo_object_id
        ),
    tp AS (
        SELECT practice."name" as practice_name, cirkwi."name" as cirkwi_name, practice.id
        FROM trekking_practice practice
        LEFT JOIN cirkwi_cirkwilocomotion cirkwi ON cirkwi.id = practice.cirkwi_id
        )
SELECT
    t.topo_object_id AS eid,
    string_agg(ats."name", ',') AS proprietaire,
    NULL::text AS contact, -- adresse mail à renseigner
    NULL::text AS uuid, -- pas d'uuid prévu dans Geotrek
    -- construction de l'url valable pour Geotrek-rando V2
    'https://urlduportailgeotrekrando/' || lower(unaccent(replace(tp.practice_name, ' ', '-'))) || '/'
    || lower(unaccent(replace(btrim(regexp_replace(t."name", '[^\w -]', '', 'g')), ' ', '-'))) || '/' AS url,
    -- pour Geotrek-rando V3, essayer quelque chose comme : 'urlportail/trek/' || 't.topo_object_id' || '-' || unaccent(regexp_replace(btrim(regexp_replace(t."name", '[^- ()\w]', '', 'g')), '\W', '-'))  (non essayé)
    NULL::integer AS id_osm,
    t."name" AS nom_itineraire,
    tp.practice_name AS pratique, -- uniquement valable si vos noms de pratiques correspondent déjà au schéma, sinon passer par quelque chose comme : CASE WHEN tp.practice_name ILIKE 'Randonnée Trail' THEN 'trail'::text END AS pratique
    lower(route.route::text) AS type_itineraire,
    c.liste_noms::text AS communes_nom,
    c.liste_codes::text AS communes_code,
    btrim(t.departure) AS depart,
    btrim(t.arrival) AS arrivee,
    round(t.duration::numeric,1)::real AS duree,
    balisage.b::text AS balisage,
    top.length::integer AS longueur,
    difficulty.difficulty AS difficulte,
    NULL::text AS cotation,
    top.max_elevation AS altitude_max,
    top.min_elevation AS altitude_min,
    top.ascent AS denivele_positif,
    top.descent AS denivele_negatif,
    t.description AS instructions,
    t.ambiance AS presentation,
    t.description_teaser AS presentation_courte,
    themes.liste::text AS themes,
    t.advice AS recommandations,
    handi.liste::text AS accessibilite,
    t.access AS acces_routier,
    t.public_transport AS transports,
    jsonb_build_object( -- construction de l'objet GeoJSON parking, avec une géométrie correspondant au champ t.parking_location et une propriété infos_parking correspondant au champ t.advised_parking
        'type',       'Feature',
        'properties', jsonb_build_object('infos_parking', advised_parking),
        'geometry',   ST_AsGeoJSON(st_snaptogrid(st_transform(parking_location, 4326), 0.000027::double precision))::jsonb    
        ) AS parking,
    date(top.date_insert) AS date_creation,
    date(top.date_update) AS date_modification,
    medias.liste AS medias,
    parent.parent_id AS itineraire_parent,
    sol.liste::text AS type_sol,
    -- réduction de la précision des coordonnées à 5 décimales, simplification de la géométrie pour réduire le nombre de points. Poids de la géométrie divisé par 7.5
    ST_AsGeoJSON(st_simplifypreservetopology(st_snaptogrid(st_transform(top.geom, 4326), 0.000027::double precision), 0.000027::double precision)) AS geometrie 
FROM selected_t t
LEFT JOIN core_topology top ON t.topo_object_id = top.id
LEFT JOIN sources ON t.topo_object_id = sources.trek_id
LEFT JOIN authent_structure ats ON ats.id = t.structure_id
LEFT JOIN tp ON tp.id = t.practice_id
LEFT JOIN trekking_route route ON t.route_id = route.id
LEFT JOIN trekking_difficultylevel difficulty ON difficulty.id = t.difficulty_id
LEFT JOIN handi ON t.topo_object_id = handi.trek_id
LEFT JOIN trekking_orderedtrekchild parent ON t.topo_object_id = parent.child_id
LEFT JOIN themes ON t.topo_object_id = themes.trek_id
LEFT JOIN medias ON t.topo_object_id = medias.object_id
LEFT JOIN balisage ON t.topo_object_id = balisage.trek_id
LEFT JOIN sol ON t.topo_object_id = sol.topo_object_id
LEFT JOIN LATERAL ( -- construction des listes des noms de commune et des codes INSEE
    SELECT string_agg(z."name", ',') AS liste_noms, string_agg(z.code, ',') AS liste_codes, c_1.id
    FROM core_topology c_1
    JOIN zoning_city z ON t.topo_object_id = c_1.id AND st_intersects(c_1.geom, z.geom)
    GROUP BY c_1.id
    ) c ON true
GROUP BY t.topo_object_id, t."name", tp.practice_name, tp.cirkwi_name, route.route, c.liste_noms, c.liste_codes,
t.departure, t.arrival, t.duration, balisage.b, top.length, difficulty.difficulty,
top.max_elevation, top.min_elevation, top.ascent, top.descent, t.description, t.ambiance,
t.description_teaser, themes.liste, handi.liste, t.advice, t."access", t.public_transport, medias.liste,
t.parking_location, t.advised_parking, top.date_insert, top.date_update, parent.parent_id, sol.liste, top.geom;