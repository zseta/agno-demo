-- =============================================================================
-- ScyllaDB schema for the agno + ScyllaDB vector store demo
-- Generated from a live cluster (ScyllaDB 2026.2 + vector-store 1.8.0)
-- via: DESCRIBE KEYSPACE agno_keyspace;
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Keyspace
--    NetworkTopologyStrategy with tablets enabled (ScyllaDB recommended)
--    Requires --enable-cassio-compatibility 1 on the ScyllaDB node so that
--    cassio's ENTRIES map index is rewritten as a regular secondary index.
-- ---------------------------------------------------------------------------

CREATE KEYSPACE IF NOT EXISTS agno_keyspace
    WITH replication = {'class': 'NetworkTopologyStrategy', 'datacenter1': '1'}
    AND tablets = {'enabled': true};


-- ---------------------------------------------------------------------------
-- 2. Vector table
--    Created automatically by cassio (via agno.vectordb.cassandra.Cassandra)
--    when the first Cassandra() object is instantiated.
--
--    Columns
--    -------
--    row_id         TEXT  – UUID string; primary key / document chunk id
--    attributes_blob TEXT  – JSON bag of extra cassio-managed attributes
--    body_blob       TEXT  – plain-text content of the document chunk
--    document_name   TEXT  – the name= value passed to knowledge.insert()
--    metadata_s      MAP<TEXT,TEXT> – arbitrary key/value metadata dict
--                             (e.g. {"doc_type": "recipe_book", ...})
--    vector          VECTOR<FLOAT, 384> – embedding produced by
--                             SentenceTransformerEmbedder (all-MiniLM-L6-v2)
--
--    NOTE: agno's Cassandra class hardcodes vector_dimension=1024 in
--    initialize_table(); the demo subclass (CassandraWithDims) passes
--    embedder.dimensions (384) instead.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS agno_keyspace.knowledge_st (
    row_id        text,
    attributes_blob text,
    body_blob     text,
    document_name text,
    metadata_s    map<text, text>,
    vector        vector<float, 384>,
    PRIMARY KEY (row_id)
);


-- ---------------------------------------------------------------------------
-- 3. Indexes
--    Also created automatically by cassio on table initialisation.
-- ---------------------------------------------------------------------------

-- ANN (Approximate Nearest Neighbour) index on the vector column.
-- Powers ORDER BY vector ANN OF <query_vector> queries.
-- ScyllaDB routes these to the vector-store service (port 6080).
CREATE CUSTOM INDEX IF NOT EXISTS idx_vector_knowledge_st
    ON agno_keyspace.knowledge_st (vector)
    USING 'vector_index';

-- Secondary index on the ENTRIES of the metadata_s map.
-- Allows filtering by individual metadata key/value pairs.
-- Requires --enable-cassio-compatibility 1 on ScyllaDB (otherwise cassio
-- tries to use SAI on map entries, which ScyllaDB does not support).
CREATE INDEX IF NOT EXISTS eidx_metadata_s_knowledge_st
    ON agno_keyspace.knowledge_st (entries(metadata_s));


-- =============================================================================
-- Query patterns issued by cassio / agno at runtime
-- =============================================================================

-- ---------------------------------------------------------------------------
-- INSERT  (knowledge.insert / knowledge.ainsert)
-- One row per document chunk; vector is the embedding of body_blob.
-- ---------------------------------------------------------------------------

INSERT INTO agno_keyspace.knowledge_st
    (row_id, body_blob, document_name, metadata_s, vector, attributes_blob)
VALUES
    (?, ?, ?, ?, ?, ?);


-- ---------------------------------------------------------------------------
-- ANN vector search  (agent.print_response / agent.aprint_response)
-- The agent calls search_knowledge_base(), which runs this query.
-- Returns the <n> chunks whose embedding is closest to the query vector.
-- Optional WHERE clause is added when metadata filters are present.
-- ---------------------------------------------------------------------------

SELECT row_id, body_blob, document_name, metadata_s, attributes_blob
    FROM agno_keyspace.knowledge_st
    ORDER BY vector ANN OF ?
    LIMIT ?;

-- … with a metadata filter (e.g. when knowledge filters are applied):
SELECT row_id, body_blob, document_name, metadata_s, attributes_blob
    FROM agno_keyspace.knowledge_st
    WHERE metadata_s['doc_type'] = ?
    ORDER BY vector ANN OF ?
    LIMIT ?;


-- ---------------------------------------------------------------------------
-- SELECT by primary key  (internal cassio row look-up)
-- ---------------------------------------------------------------------------

SELECT row_id, body_blob, document_name, metadata_s, attributes_blob
    FROM agno_keyspace.knowledge_st
    WHERE row_id = ?;


-- ---------------------------------------------------------------------------
-- DELETE by primary key  (vector_db.delete_by_name / delete_by_metadata)
-- cassio resolves matching row_ids first (via SELECT), then issues one
-- DELETE per row.
-- ---------------------------------------------------------------------------

DELETE FROM agno_keyspace.knowledge_st
    WHERE row_id = ?;


-- ---------------------------------------------------------------------------
-- SELECT for delete_by_name
-- Finds all chunks belonging to a named document set, then deletes them.
-- ---------------------------------------------------------------------------

SELECT row_id
    FROM agno_keyspace.knowledge_st
    WHERE document_name = ?;    -- document_name has no dedicated index;
                                -- this is a filtered full-scan internally.


-- ---------------------------------------------------------------------------
-- SELECT for delete_by_metadata
-- Finds rows where a metadata key matches, using the ENTRIES index.
-- ---------------------------------------------------------------------------

SELECT row_id
    FROM agno_keyspace.knowledge_st
    WHERE metadata_s['doc_type'] = ?;
