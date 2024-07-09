import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;

mongo.Db? db;
String? userRole;
String? currentUserLogin;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  db = await mongo.Db.create(
      "mongodb+srv://admin:admin@cluster0.lkbdzcr.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0");
  await db?.open();
  print('Connected to database');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Map Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SignInPage(),
    );
  }
}

class SignInPage extends StatefulWidget {
  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sign In'),
      ),
      body: Column(
        children: <Widget>[
          TextField(
            controller: _loginController,
            decoration: InputDecoration(
              labelText: 'Login',
            ),
          ),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Password',
            ),
            obscureText: true,
          ),
          ElevatedButton(
            onPressed: _isLoading
                ? null
                : () async {
                    setState(() {
                      _isLoading = true;
                    });
                    final String login = _loginController.text;
                    final String password = _passwordController.text;

                    bool isAuthenticated =
                        await authenticateUser(login, password);

                    if (isAuthenticated) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => MapPage(),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Authentication failed')),
                      );
                    }

                    setState(() {
                      _isLoading = false;
                    });
                  },
            child: _isLoading ? CircularProgressIndicator() : Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Future<bool> authenticateUser(String login, String password) async {
    try {
      var db = await mongo.Db.create(
          "mongodb+srv://admin:admin@cluster0.lkbdzcr.mongodb.net/test?retryWrites=true&w=majority&appName=Cluster0");
      await db.open();
      var collection = db.collection('user');
      var user = await collection
          .findOne(mongo.where.eq('login', login).eq('password', password));

      if (user != null) {
        userRole = user['role'];
        currentUserLogin = user['login'];
      }

      await db.close();
      return user != null;
    } catch (e) {
      print('Authentication Error: $e');
      return false;
    }
  }
}

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _controller;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    var collection = db?.collection('points');
    var query = userRole == 'admin'
        ? mongo.SelectorBuilder()
        : mongo.where.eq('user', currentUserLogin);

    var points = await collection?.find(query).toList();
    setState(() {
      _markers = points?.map((point) {
        LatLng latLng = LatLng(point['latitude'], point['longitude']);
        bool pickedUp = point['pickedUp'];
        return Marker(
          markerId: MarkerId(point['_id'].toString()),
          position: latLng,
          onTap: () async {
            if (userRole != 'admin' && !pickedUp) {
              await _pickUpPoint(point);
            } else if (userRole == 'admin') {
              _showAdminActionsDialog(point);
            }
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(
              pickedUp ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed),
        );
      }).toSet() ?? {};
    });
  }

  Future<void> _addMarker(LatLng latLng) async {
    String? selectedUser = await _showUserSelectionDialog();
    if (selectedUser != null) {
      var collection = db?.collection('points');
      await collection?.insertOne({
        'latitude': latLng.latitude,
        'longitude': latLng.longitude,
        'user': selectedUser,
        'pickedUp': false,
      });
      _loadMarkers();
    }
  }

  Future<String?> _showUserSelectionDialog() async {
    var collection = db?.collection('user');
    var users = await collection?.find().toList();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select User'),
          content: users != null
              ? SingleChildScrollView(
                  child: Column(
                    children: users.map((user) {
                      return ListTile(
                        title: Text(user['login']),
                        onTap: () {
                          Navigator.pop(context, user['login']);
                        },
                      );
                    }).toList(),
                  ),
                )
              : CircularProgressIndicator(),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickUpPoint(Map<String, dynamic> point) async {
    var collection = db?.collection('points');
    await collection?.updateOne(
      mongo.where.id(point['_id']),
      mongo.modify.set('pickedUp', true),
    );
    _loadMarkers();
  }

  Future<void> _deletePoint(Map<String, dynamic> point) async {
    var collection = db?.collection('points');
    await collection?.deleteOne(mongo.where.id(point['_id']));
    _loadMarkers();
  }

  void _showAdminActionsDialog(Map<String, dynamic> point) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Admin Actions'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Delete Point'),
                onTap: () async {
                  await _deletePoint(point);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Map'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => SignInPage()),
                );
              } else if (value == 'addUser' && userRole == 'admin') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => AddUserPage()),
                );
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Text('Logout'),
                ),
                if (userRole == 'admin')
                  PopupMenuItem<String>(
                    value: 'addUser',
                    child: Text('Add User'),
                  ),
              ];
            },
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(53.8667, 21.3050),
          zoom: 13.0,
        ),
        onMapCreated: (GoogleMapController controller) {
          _controller = controller;
        },
        markers: _markers,
        onTap: (LatLng latLng) {
          if (userRole == 'admin') {
            _addMarker(latLng);
          }
        },
        mapType: MapType.satellite, // Set the map type to satellite
        minMaxZoomPreference: MinMaxZoomPreference(0, 20), // Zwiększenie maksymalnego zoomu
      ),
    );
  }
}

class AddUserPage extends StatelessWidget {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add User'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _loginController,
              decoration: InputDecoration(
                labelText: 'Login',
              ),
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
              ),
              obscureText: true,
            ),
            TextField(
              controller: _roleController,
              decoration: InputDecoration(
                labelText: 'Role',
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final String login = _loginController.text;
                final String password = _passwordController.text;
                final String role = _roleController.text;

                await addUser(login, password, role);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('User added successfully')),
                );

                Navigator.of(context).pop();
              },
              child: Text('Add User'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> addUser(String login, String password, String role) async {
    try {
      var db = await mongo.Db.create(
          "mongodb+srv://admin:admin@cluster0.lkbdzcr.mongodb.net/test?retryWrites=true&w=majority&appName=Cluster0");
      await db.open();
      var collection = db.collection('user');
      await collection.insertOne({
        'login': login,
        'password': password,
        'role': role,
      });
      await db.close();
    } catch (e) {
      print('Add User Error: $e');
    }
  }
}
