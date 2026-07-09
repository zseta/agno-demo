-- =============================================================================
-- Schema for the agno + ScyllaDB vector store demo
--
-- DDL shown below is what cassio (the library agno uses internally) sends to
-- the database. Inline comments mark where ScyllaDB stores a different form.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Keyspace
--    cassio does not create the keyspace; demo.py creates it explicitly.
--    SimpleStrategy is the cassio default; here we use NetworkTopologyStrategy
--    with tablets (ScyllaDB recommended).
-- ---------------------------------------------------------------------------

-- What cassio / the docs suggest:
-- CREATE KEYSPACE IF NOT EXISTS agno_keyspace
--     WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 1};

-- What this demo creates (ScyllaDB-optimised):
CREATE KEYSPACE IF NOT EXISTS agno_keyspace
    WITH replication = {'class': 'NetworkTopologyStrategy', 'datacenter1': '1'}
    AND tablets = {'enabled': true};


-- ---------------------------------------------------------------------------
-- 2. Vector table
--    Sent by cassio verbatim; ScyllaDB stores it unchanged.
--
--    Columns
--    -------
--    row_id          TEXT            UUID string; primary key / chunk id
--    attributes_blob TEXT            JSON bag of extra cassio attributes
--    body_blob       TEXT            plain-text content of the chunk
--    document_name   TEXT            name= value passed to knowledge.insert()
--    metadata_s      MAP<TEXT,TEXT>  arbitrary key/value metadata
--    vector          VECTOR<FLOAT,N> embedding vector
--
--    NOTE: cassio receives vector_dimension as a constructor argument.
--    agno's Cassandra class hardcodes 1024; the demo subclass (CassandraWithDims)
--    passes embedder.dimensions (384 for all-MiniLM-L6-v2) instead.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS agno_keyspace.knowledge_st (
    row_id          text,
    attributes_blob text,
    body_blob       text,
    document_name   text,
    metadata_s      map<text, text>,
    vector          vector<float, 384>,
    PRIMARY KEY (row_id)
);


-- ---------------------------------------------------------------------------
-- 3. Indexes
--    cassio runs these DDL statements during table initialisation.
--    ScyllaDB silently rewrites the metadata index (see below).
-- ---------------------------------------------------------------------------

-- 3a. ANN vector index
--     cassio sends:
CREATE CUSTOM INDEX IF NOT EXISTS idx_vector_knowledge_st
    ON agno_keyspace.knowledge_st (vector)
    USING 'org.apache.cassandra.index.sai.StorageAttachedIndex';
--
-- ScyllaDB stores it as:
--   CREATE CUSTOM INDEX idx_vector_knowledge_st
--       ON agno_keyspace.knowledge_st (vector)
--       USING 'vector_index';
--
-- ScyllaDB translates the generic SAI declaration into its own vector_index
-- type and delegates ANN queries to the vector-store sidecar (port 6080).


-- 3b. Metadata map ENTRIES index
--     cassio sends:
CREATE CUSTOM INDEX IF NOT EXISTS eidx_metadata_s_knowledge_st
    ON agno_keyspace.knowledge_st (ENTRIES(metadata_s))
    USING 'org.apache.cassandra.index.sai.StorageAttachedIndex';
--
-- ScyllaDB stores it as:
--   CREATE INDEX eidx_metadata_s_knowledge_st
--       ON agno_keyspace.knowledge_st (entries(metadata_s));
--
-- ScyllaDB does not support SAI on map ENTRIES. With the flag
-- --enable-cassio-compatibility 1 it rewrites the statement as a regular
-- secondary index instead of rejecting it.
-- This index powers the WHERE metadata_s['key'] = ? filter used by
-- delete_by_metadata() and filtered ANN searches.


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
