import "dart:async";

import "package:sqljocky/sqljocky.dart";
import "package:dslink/client.dart";
import "package:dslink/responder.dart";
import "package:dslink/common.dart";

LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(
    args,
    "MySQL-",
    defaultNodes: {
      "Create_Connection": {
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
      "queryData": (String path) => new QueryDataNode(path),
      "query": (String path) => new QueryNode(path),
      "deleteConnection": (String path) => new DeleteConnectionNode(path),
      "createConnection": (String path) => new CreateConnectionNode(path)
    }
  );

  link.save();
  link.connect();
}

class CreateConnectionNode extends SimpleNode {
  CreateConnectionNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    link.provider.addNode("/${params["name"]}", {
      r"$is": "connection",
      r"$mysql_host": params["host"],
      r"$mysql_port": params["port"],
      r"$$mysql_user": params["user"],
      r"$$mysql_password": params["password"],
      r"$mysql_db": params["db"],
      "Delete_Connection": {
        r"$name": "Delete Connection",
        r"$is": "deleteConnection",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [],
        r"$columns": []
      },
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
      "Query": {
        r"$name": "Query",
        r"$is": "query",
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
      }
    });

    link.save();

    return {};
  }
}

class ConnectionNode extends SimpleNode {
  ConnectionNode(String path) : super(path);

  @override
  void onCreated() {
    var host = get(r"$mysql_host");
    var port = get(r"$mysql_port");
    var user = get(r"$$mysql_user");
    var password = get(r"$$mysql_password");
    var db = get(r"$mysql_db");

    print("Connect to ${host}:${port}/${db} using ${user}:${password}");

    pools[path.split("/")[1]] = new ConnectionPool(host: host, user: user, port: port, db: db, password: password);
  }
}

class DeleteConnectionNode extends SimpleNode {
  DeleteConnectionNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    link.provider.removeNode(new Path(path).parentPath);
    link.save();
    return {};
  }
}

class QueryNode extends SimpleNode {
  QueryNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var query = params["query"];
    Results results = await getConnectionPool(this).query(query);
    return {
      "affected": results.affectedRows,
      "insertId": results.insertId
    };
  }
}

class QueryDataNode extends SimpleNode {
  QueryDataNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    var r = new AsyncTableResult();
    r.columns = ["name"];
    var query = params["query"];
    new Future(() async {
      Results results = await getConnectionPool(this).query(query);
      r.columns = await results.fields.map((it) => {
        "name": it.name,
        "type": "dynamic"
      }).toList();
      results.listen((Row row) {
        r.update([row.toList()]);
      }).onDone(() {
        r.close();
      });
    });
    return r;
  }
}

ConnectionPool getConnectionPool(SimpleNode node) {
  var n = node.path.split("/")[1];
  return pools[n];
}

Map<String, ConnectionPool> pools = {};
