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
              "type": "string"
            },
            {
              "name": "host",
              "type": "string"
            },
            {
              "name": "port",
              "type": "number",
              "default": 3306
            },
            {
              "name": "user",
              "type": "string",
              "default": "root"
            },
            {
              "name": "password",
              "type": "string"
            },
            {
              "name": "db",
              "type": "string"
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
                r.update([row.toList()]);
              }, onDone: () {
                r.close();
              }, onError: (e) {
                r.close();
              });
            } catch (e) {
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
            return {};
          }
        }),
        "listTables": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) async {
          try {
            Results results = await getConnectionPool(path).query("SHOW TABLES");
            return results.expand((x) => x).map((x) => {
              "name": x
            }).toList();
          } catch (e) {
            return [];
          }
        }),
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

          for (var field in ["host", "port", "user", "password", "db"]) {
            var val = params[field];
            var nn = "\$mysql_${field}";
            var old = params[nn];

            if (nn == null) {
              nn = "\$\$mysql_${field}";
              old = params[nn];
            }

            if (val != null && old != val) {
              conn.configs[nn] = val;
            }
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
        })
      },
      autoInitialize: false
  );

  link.init();
  link.connect();
  link.save();
}

class CreateConnectionNode extends SimpleNode {
  CreateConnectionNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    link.addNode("/${params["name"]}", {
      r"$is": "connection",
      r"$mysql_host": params["host"],
      r"$mysql_port": params["port"],
      r"$$mysql_user": params["user"],
      r"$$mysql_password": params["password"],
      r"$mysql_db": params["db"]
    });

    link.save();

    return {};
  }
}

class ConnectionNode extends SimpleNode {
  ConnectionNode(String path) : super(path);

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

    var pool = new ConnectionPool(host: host, user: user, port: port, db: db, password: password);

    RetainedConnection rc = await pool.getConnection();
    await rc.release();

    if (pools.containsKey(name)) {
      pools[name].close();
      pools.remove(name);
    }

    pools[name] = pool;

    var x = {
      "Query_Data": {
        r"$name": "Query Data",
        r"$is": "queryData",
        r"$invokable": "write",
        r"$result": "table",
        r"$params": [
          {
            "name": "query",
            "type": "string"
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
            "type": "string"
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
            "default": password
          },
          {
            "name": "db",
            "type": "string",
            "default": db
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
  DeleteConnectionNode(String path) : super(path);

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
