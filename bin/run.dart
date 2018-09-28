import "dart:async";

import "package:sqljocky/sqljocky.dart";
import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(
      args,
      "MySQL-",
      defaultNodes: {
        "Create_Connection": {
          r"$name": "Create Connection",
          r"$is": "createConnection",
          r"$invokable": "write",
          r"$params": [
            {
              "name": "name",
              "type": "string",
              "description": "Connection Name",
              "placeholder": "mydb"
            },
            {
              "name": "host",
              "type": "string",
              "default": "localhost",
              "description": "Server Host",
              "placeholder": "localhost"
            },
            {
              "name": "port",
              "type": "number",
              "default": 3306,
              "description": "Server Port",
              "placeholder": "3306"
            },
            {
              "name": "user",
              "type": "string",
              "default": "root",
              "description": "User",
              "placeholder": "root"
            },
            {
              "name": "password",
              "type": "string",
              "description": "User Password (Optional)",
              "placeholder": "!MyPassword!",
              "editor": "password"
            },
            {
              "name": "db",
              "type": "string",
              "description": "Database Name",
              "placeholder": "mydb"
            },
            {
              "name": "useSSL",
              "type": "bool",
              "default": false
            }
          ]
        }
      },
      profiles: {
        "connection": (String path) => new ConnectionNode(path),
        "queryData": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
          var r = new AsyncTableResult();
          r.columns = ["name"];
          var query = params["query"];
          new Future(() async {
            try {
              Results results = await getConnectionPool(path).query(query);
              r.columns = await results.fields.map((it) => {
                "name": it.name,
                "type": "dynamic"
              }).toList();
              results.listen((Row row) {
                var out = [];
                for (var x in row) {
                  if (x is Blob || x is DateTime) {
                    out.add(x.toString());
                  } else {
                    out.add(x);
                  }
                }
                r.update([out]);
              }, onDone: () {
                if (r.rows == null || r.rows.isEmpty) {
                  r.update([]);
                }
                r.close();
              }, onError: (e) {
                r.columns = [
                  {
                    "name": "error",
                    "type": "string"
                  }
                ];
                r.update([
                  {
                    "error": e.toString()
                  }
                ]);
                r.close();
              });
            } catch (e) {
              r.columns = [
                {
                  "name": "error",
                  "type": "string"
                }
              ];
              r.update([
                {
                  "error": e.toString()
                }
              ]);
              r.close();
            }
          });
          return r;
        }),
        "execute": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) async {
          try {
            var query = params["query"];
            Results results = await getConnectionPool(path).query(query);
            return {
              "affected": results.affectedRows,
              "insertId": results.insertId
            };
          } catch (e) {
            return {
              "error": e.toString()
            };
          }
        }, link.provider),
        "listTables": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) async {
          try {
            Results results = await getConnectionPool(path).query("SHOW TABLES");
            return results.expand((x) => x).map((x) => {
              "name": x
            }).toList();
          } catch (e) {
            return [];
          }
        }, link.provider),
        "deleteConnection": (String path) => new DeleteConnectionNode(path),
        "createConnection": (String path) => new CreateConnectionNode(path),
        "editConnection": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) async {
          var name = params["name"];
          var oldName = path.split("/")[1];
          ConnectionNode conn = link["/${oldName}"];
          if (name != null && name != oldName) {
            if ((link.provider as SimpleNodeProvider).nodes.containsKey("/${name}")) {
              return {
                "success": false,
                "message": "Connection '${name}' already exists."
              };
            } else {
              var n = conn.serialize(false);
              link.removeNode("/${oldName}");
              link.addNode("/${name}", n);
              (link.provider as SimpleNodeProvider).nodes.remove("/${oldName}");
              conn = link["/${name}"];
            }
          }

          link.save();

          var mmm = [];

          for (var field in ["host", "port", "user", "password", "db"]) {
            var val = params[field];
            var nn = "\$mysql_${field}";
            var old = conn.configs[nn];

            if (old == null) {
              nn = "\$\$mysql_${field}";
              old = conn.configs[nn];
            }

            if (val != null && old != val) {
              conn.configs[nn] = val;

              mmm.add(nn);
            }
          }

          if (mmm.length == 1 && mmm.first == r"$mysql_db") {
            var pool = getConnectionPool(conn.path);
            var c = await pool.getConnection();
            var db = params["db"];
            await c.query("USE ${db}");
          }

          try {
            await conn.setup();
          } catch (e) {
            return {
              "success": false,
              "message": "Failed to connect to database: ${e}"
            };
          }

          link.save();

          return {
            "success": true,
            "message": "Success!"
          };
        }, link.provider)
      },
      autoInitialize: false
  );

  link.init();
  link.connect();
  link.save();
}

class CreateConnectionNode extends SimpleNode {
  CreateConnectionNode(String path) : super(path, link.provider);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var name = params["name"];

    var host = params["host"];
    var port = params["port"];
    var user = params["user"];
    var password = params["password"];
    var db = params["db"];
    var useSSL = params["useSSL"];

    var m = {
      r"$is": "connection",
      r"$mysql_host": host,
      r"$mysql_port": port,
      r"$$mysql_user": user,
      r"$$mysql_password": password,
      r"$mysql_ssl": useSSL
    };

    if (db != null) {
      m[r"$mysql_db"] = db;
    }

    link.addNode("/${name}", m);
    link.save();

    return {};
  }
}

class ConnectionNode extends SimpleNode {
  ConnectionNode(String path) : super(path, link.provider);

  @override
  void onCreated() {
    setup();
  }

  setup() async {
    var name = new Path(path).name;

    var host = get(r"$mysql_host");
    var port = get(r"$mysql_port");
    var user = get(r"$$mysql_user");
    var password = get(r"$$mysql_password");
    var db = get(r"$mysql_db");
    var useSSL = get(r"$mysql_ssl");

    var pool = new ConnectionPool(host: host, user: user, port: port, db: db, password: password, useSSL: useSSL);

    try {
      RetainedConnection rc = await pool.getConnection();
      await rc.release();
    } catch (e) {
    }

    if (pools.containsKey(name)) {
      pools[name].closeConnectionsNow();
      pools.remove(name);
    }

    pools[name] = pool;

    var x = {
      "Query_Data": {
        r"$name": "Query Data",
        r"$is": "queryData",
        r"$invokable": "write",
        r"$result": "stream",
        r"$params": [
          {
            "name": "query",
            "type": "string",
            "description": "Database Query",
            "placeholder": "SHOW TABLES"
          }
        ],
        r"$columns": [
          {
            "name": "output",
            "type": "tabledata"
          }
        ]
      },
      "Execute": {
        r"$name": "Execute",
        r"$is": "execute",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [
          {
            "name": "query",
            "type": "string",
            "description": "Database Query",
            "placeholder": "INSERT INTO table_name (column1,column2) VALUES (value1,value2);"
          }
        ],
        r"$columns": [
          {
            "name": "affected",
            "type": "integer"
          },
          {
            "name": "insertId",
            "type": "integer"
          },
          {
            "name": "error",
            "type": "string"
          }
        ]
      },
      "List_Tables": {
        r"$name": "List Tables",
        r"$result": "table",
        r"$is": "listTables",
        r"$invokable": "write",
        r"$columns": [
          {
            "name": "name",
            "type": "string"
          }
        ]
      },
      "Edit_Connection": {
        r"$name": "Edit Connection",
        r"$is": "editConnection",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [
          {
            "name": "name",
            "type": "string",
            "default": name
          },
          {
            "name": "host",
            "type": "string",
            "default": host
          },
          {
            "name": "port",
            "type": "number",
            "default": port
          },
          {
            "name": "user",
            "type": "string",
            "default": user
          },
          {
            "name": "password",
            "type": "string",
            "default": password,
            "editor": "password"
          },
          {
            "name": "db",
            "type": "string",
            "default": db
          },
          {
            "name": "useSSL",
            "type": "bool",
            "default": false
          }
        ],
        r"$columns": [
          {
            "name": "success",
            "type": "bool"
          },
          {
            "name": "message",
            "type": "string"
          }
        ]
      },
      "Delete_Connection": {
        r"$name": "Delete Connection",
        r"$is": "deleteConnection",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [],
        r"$columns": []
      }
    };

    for (var a in x.keys) {
      link.removeNode("${path}/${a}");
      link.addNode("${path}/${a}", x[a]);
    }
  }
}

class DeleteConnectionNode extends SimpleNode {
  DeleteConnectionNode(String path) : super(path, link.provider);

  @override
  onInvoke(Map<String, dynamic> params) {
    link.removeNode(new Path(path).parentPath);
    link.save();
    return {};
  }
}

ConnectionPool getConnectionPool(String path) {
  var n = path.split("/")[1];
  return pools[n];
}

Map<String, ConnectionPool> pools = {};
