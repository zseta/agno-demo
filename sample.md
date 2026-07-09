# Sample Notes

These are sample notes used to demonstrate local-file async loading via `knowledge.ainsert(path=...)`.

## ScyllaDB

ScyllaDB is a high-performance, low-latency NoSQL database compatible with Apache Cassandra.
It is written in C++ and designed to take full advantage of modern hardware.

Key features:
- Drop-in Cassandra replacement with the same CQL interface
- Built-in vector search support via the ScyllaDB Vector Store service
- Tablets for efficient data distribution and rebalancing
- Sub-millisecond P99 latency at high throughput

## Agno

Agno is a lightweight Python framework for building AI agents.
It provides built-in integrations with vector databases (including Cassandra/ScyllaDB)
for knowledge-augmented retrieval, enabling agents to answer questions grounded
in your own documents.
