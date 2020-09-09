# MySQL DSLink (dslink-dart-mysql)

* Dart - version 1.17 and up.
* [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0)

## Overview

A DSLink to make queries to MySQL databases.

If you are not familiar with DSA, an overview can be found at
[here](http://iot-dsa.org/get-started/how-dsa-works).

This link was built using the Java DSLink SDK which can be found
[here](https://github.com/IOT-DSA/sdk-dslink-dart).

## Link Architecture

These are nodes defined by this link:

- _Main Node_ - Used to add new MySQL database connections. Default main node name is **MySQL**.
  - _Connection Node_ - Used to execute queries to the database.


## Node Guide

The following section provides descriptions of nodes in the link as well as
descriptions of actions, values and child nodes.


### Main Node

This is the root node of the link.  Use it to create connections to MySQL database servers.

#### Actions

1. Create Connection - Adds a connection to MySQL database.  

<img src="https://github.com/IOT-DSA/docs/blob/master/images/external/mysql-create-connection.png" width="400" alt="Create Connection">

The parameters are:
  - **name** - What to name the connection node in the tree.
  - **host** - MySQL server host name or IP.
  - **port** - MySQL server port. Default: 3306
  - **user** - User account used to authenticate with the database server.
  - **password** - Password for the user account.
  - **db** - Database name to use by default.

#### Child Nodes

- Connection Node - Connections configured for specific servers and account.

### Connection Node

Each connection node represents a MySQL server and a specific account to access it.

#### Actions

1. Query Data - Sends custom query to read information from the database. The parameters are:
    - **query** - SQL query string.
    - **output** - resulting table with rows and columns requested.
1. Execute - Sends a custom query to add or update information in the database. The parameters are:
    - **query** - SQL query with INSERT, UPDATE, DELETE request.
    - **affected** - returns number of rows affected by the query.
    - **insertId** - if the query is an INSERT statement, returns ID of the added record.
1. List Tables - returns a list of all the tables in the database. The parameters are:
    - **output** - the resulting table with the list of database tables.
1. Edit Connection - changes configuration for this connection node. The parameters are exactly the same as for **Create Connection** action above.
1. Delete Connection - deletes current connection to the database.

## Examples

### Query a Table

1. Create a new connection to your database.
1. Drag and drop **Query Data** action to the dataflow.
1. In the block's **query** parameter enter your SQL SELECT statement. For example, _SELECT * FROM users_
1. Trigger **Invoke** action on a block.
1. The resulting table with the rows from the database will be available under **output** parameter.

<img src="https://github.com/IOT-DSA/docs/blob/master/images/external/mysql-example-query.png" width="1000" alt="Select Query">
