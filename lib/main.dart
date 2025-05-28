// Gerekli Dart ve Flutter paketlerini import ediyoruz.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Araba Kontrol',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Color(0xFF212121),
        // Butonlar için genel bir tema yerine GestureDetector içinde özel stil kullanacağız.
      ),
      home: BluetoothControlPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothControlPage extends StatefulWidget {
  @override
  _BluetoothControlPageState createState() => _BluetoothControlPageState();
}

class _BluetoothControlPageState extends State<BluetoothControlPage> {
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection? _connection;
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _selectedDevice;
  bool _isConnecting = false;
  bool get isConnected => _connection != null && _connection!.isConnected;

  double _speed = 50.0;
  bool _isCurrentlyDiscovering = false;
  StreamSubscription<BluetoothDiscoveryResult>? _discoveryResultSubscription;

  // Hangi butonun basılı olduğunu takip etmek ve rengini değiştirmek için.
  // Değer olarak butonun 'command' karakterini tutacak.
  String? _pressedButtonCommand;

  @override
  void initState() {
    super.initState();
    _initializeBluetoothAndPermissions();
  }

  @override
  void dispose() {
    _discoveryResultSubscription?.cancel();
    _connection?.dispose();
    _connection = null;
    super.dispose();
  }

  Future<void> _initializeBluetoothAndPermissions() async {
    bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted) {
      if (mounted) {
        setState(() {
          _bluetoothState = BluetoothState.STATE_OFF;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bluetooth ve konum izinleri uygulamanın çalışması için gereklidir.',
            ),
          ),
        );
      }
      return;
    }

    FlutterBluetoothSerial.instance.state.then((state) {
      if (!mounted) return;
      setState(() {
        _bluetoothState = state;
        if (_bluetoothState == BluetoothState.STATE_ON) {
          _checkBluetoothStatusAndDiscover();
        }
      });
    });

    _bluetooth.onStateChanged().listen((BluetoothState state) {
      if (!mounted) return;
      setState(() {
        _bluetoothState = state;
        if (_bluetoothState == BluetoothState.STATE_OFF) {
          _selectedDevice = null;
          _isConnecting = false;
          _isCurrentlyDiscovering = false;
          _devicesList.clear();
          _discoveryResultSubscription?.cancel();
          if (isConnected) _disconnect();
        } else if (_bluetoothState == BluetoothState.STATE_ON) {
          _checkBluetoothStatusAndDiscover();
        }
      });
    });
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = {};
    List<Permission> permissionsToRequest = [
      Permission.locationWhenInUse, // Her zaman önce konumu isteyin
    ];

    if (Platform.isAndroid) {
      // Android 12 (API 31) ve üzeri için yeni Bluetooth izinleri
      // Bu izinler sadece `targetSdkVersion` 31+ ise sistem tarafından istenir.
      permissionsToRequest.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ]);
    }
    // Eski Android sürümleri için (targetSdkVersion 30 ve altı),
    // BLUETOOTH ve BLUETOOTH_ADMIN izinleri manifest'ten otomatik verilir,
    // runtime'da istenmesine gerek yoktur. `permission_handler` bunu yönetir.

    print("PERMISSION_DEBUG: İzinler isteniyor: $permissionsToRequest");

    for (var permission in permissionsToRequest) {
      PermissionStatus currentStatus = await permission.status;
      print(
        "PERMISSION_DEBUG: ${permission.toString()} için mevcut durum: $currentStatus",
      );
      // Sadece 'granted' veya 'limited' (iOS için) değilse izin iste
      if (!currentStatus.isGranted && !currentStatus.isLimited) {
        print(
          "PERMISSION_DEBUG: ${permission.toString()} izni VERİLMEMİŞ, isteniyor...",
        );
        statuses[permission] = await permission.request();
        print(
          "PERMISSION_DEBUG: ${permission.toString()} istendi. Yeni durum: ${statuses[permission]}",
        );
      } else {
        print(
          "PERMISSION_DEBUG: ${permission.toString()} izni zaten VERİLMİŞ veya KISITLI. Durum: $currentStatus",
        );
        statuses[permission] = currentStatus;
      }
    }

    bool allGranted = true;
    statuses.forEach((permission, status) {
      // Android 12+ için BLUETOOTH_SCAN ve BLUETOOTH_CONNECT kritiktir.
      // Konum izni de çoğu durumda tarama için gereklidir.
      if (!status.isGranted && !status.isLimited) {
        allGranted = false;
        print(
          "PERMISSION_DEBUG: SON KONTROL - ${permission.toString()} izni VERİLMEDİ: $status",
        );
        if (status.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${_permissionToFriendlyName(permission)} izni kalıcı olarak reddedildi. Lütfen uygulama ayarlarından izin verin.',
                ),
                action: SnackBarAction(
                  label: 'Ayarlar',
                  onPressed: openAppSettings,
                ),
              ),
            );
          }
        }
      } else {
        print(
          "PERMISSION_DEBUG: SON KONTROL - ${permission.toString()} izni VERİLDİ: $status",
        );
      }
    });

    if (!allGranted)
      print("PERMISSION_DEBUG: Tüm gerekli izinler verilmedi.");
    else
      print("PERMISSION_DEBUG: Tüm gerekli izinler verildi.");
    return allGranted;
  }

  String _permissionToFriendlyName(Permission permission) {
    if (permission == Permission.bluetoothScan)
      return "Yakındaki Cihazlar (Bluetooth Tarama)";
    if (permission == Permission.bluetoothConnect)
      return "Bluetooth Bağlantısı";
    if (permission == Permission.locationWhenInUse)
      return "Konum (Uygulama Kullanılırken)";
    if (permission == Permission.location) return "Konum";
    return permission.toString().split('.').last;
  }

  Future<void> _checkBluetoothStatusAndDiscover() async {
    _bluetoothState = await FlutterBluetoothSerial.instance.state;
    if (!mounted) return;

    if (_bluetoothState.isEnabled ?? false) {
      if (!_isCurrentlyDiscovering) {
        _startDiscovery();
      }
    } else {
      setState(() {
        _isCurrentlyDiscovering = false;
        _devicesList.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bluetooth kapalı. Lütfen açın.')),
        );
      }
    }
  }

  void _startDiscovery() async {
    bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cihaz taraması için gerekli izinler alınamadı.'),
          ),
        );
      }
      return;
    }

    if (_isCurrentlyDiscovering) return;

    setState(() {
      _devicesList = [];
      _isCurrentlyDiscovering = true;
    });

    _discoveryResultSubscription?.cancel();
    _discoveryResultSubscription = _bluetooth.startDiscovery().listen(
      (BluetoothDiscoveryResult r) {
        if (!mounted) return;
        final existingIndex = _devicesList.indexWhere(
          (device) => device.address == r.device.address,
        );
        if (existingIndex < 0) {
          if (r.device.name != null && r.device.name!.isNotEmpty) {
            setState(() {
              _devicesList.add(r.device);
            });
          }
        }
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isCurrentlyDiscovering = false;
        });
        print("Cihaz tarama işlemi bitti (onDone).");
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isCurrentlyDiscovering = false;
        });
        print("Cihaz tarama hatası: $error");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tarama hatası: ${error.toString()}')),
        );
      },
      cancelOnError: true,
    );
  }

  void _connectToDevice(BluetoothDevice device) async {
    if (isConnected || _isConnecting) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zaten bağlı veya bağlanılıyor.')),
        );
      }
      return;
    }
    setState(() {
      _isConnecting = true;
      _selectedDevice = device;
    });

    if (_isCurrentlyDiscovering) {
      await _bluetooth.cancelDiscovery();
      _discoveryResultSubscription?.cancel();
      if (mounted) {
        setState(() {
          _isCurrentlyDiscovering = false;
        });
      }
    }

    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${device.name ?? device.address} cihazına bağlandı!',
            ),
          ),
        );
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Bağlantı hatası: $exception')));
        setState(() {
          _selectedDevice = null;
        });
      }
      print("Bağlantı hatası: $exception");
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _disconnect() {
    _connection?.dispose();
    _connection = null;
    _selectedDevice = null;
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Bağlantı kesildi.')));
    }
  }

  void _sendData(String data) async {
    if (isConnected) {
      try {
        _connection!.output.add(Uint8List.fromList(utf8.encode(data)));
        await _connection!.output.allSent;
        print('Gönderildi: $data');
      } catch (e) {
        print('Gönderme hatası: $e, Tip: ${e.runtimeType}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Veri gönderme hatası veya bağlantı koptu.'),
            ),
          );
          if (e.toString().toLowerCase().contains("broken pipe") ||
              e.toString().toLowerCase().contains("connection reset") ||
              e.toString().toLowerCase().contains("socket closed") ||
              e.toString().toLowerCase().contains("connection lost")) {
            _disconnect();
          }
        }
      }
    } else {
      // Bağlı değilken komut göndermeye çalışılırsa (örn: uygulama açılır açılmaz butona basılırsa)
      // veya bağlantı koptuktan sonra basılırsa.
      // Kullanıcıya bilgi verilebilir ama sürekli snackbar göstermek can sıkıcı olabilir.
      // Bu yüzden sadece konsola yazdırıyoruz.
      print('Bağlı değil, gönderilemedi: $data');
      if (mounted && (_pressedButtonCommand == null || data == 'S')) {
        // Sadece DUR komutu veya buton bırakıldığında snackbar göster.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bağlı cihaz yok! Önce bağlanın.')),
        );
      }
    }
  }

  Widget _buildConnectionBar() {
    String statusText;
    Color statusColor;

    if (!(_bluetoothState.isEnabled ?? false)) {
      statusText = 'Bluetooth veya gerekli izinler eksik/kapalı';
      statusColor = Colors.red;
    } else if (_isConnecting) {
      statusText =
          '${_selectedDevice?.name ?? _selectedDevice?.address ?? ""} cihazına bağlanılıyor...';
      statusColor = Colors.orange;
    } else if (isConnected) {
      statusText =
          '${_selectedDevice?.name ?? _selectedDevice?.address ?? ""} cihazına bağlı';
      statusColor = Colors.green;
    } else if (_isCurrentlyDiscovering) {
      statusText = 'Cihazlar aranıyor...';
      statusColor = Colors.blue;
    } else {
      statusText = 'Bağlı Değil - Cihaz Seçin';
      statusColor = Colors.grey;
    }

    return Container(
      padding: EdgeInsets.all(8.0),
      color: statusColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Text(statusText, style: TextStyle(color: Colors.white))],
      ),
    );
  }

  // --- KONTROL BUTONU OLUŞTURMA METODU (RENK DEĞİŞİMİ VE BASILI TUTMA) ---
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required String command, // Butona basıldığında gönderilecek ana komut.
    String stopCommand =
        'S', // Butondan parmak çekildiğinde gönderilecek durdurma komutu.
    Color? defaultColor, // Butonun varsayılan rengi.
    Color? pressedColor, // Buton basılıykenki rengi.
    bool mirrorIcon = false,
  }) {
    Widget iconWidget = Icon(icon, size: 30, color: Colors.white);
    if (mirrorIcon) {
      iconWidget = Transform.scale(scaleX: -1, child: iconWidget);
    }

    // Butonun o anki rengini belirle: Basılıysa pressedColor, değilse defaultColor.
    // _pressedButtonCommand, bu butonun komutuyla eşleşiyorsa buton basılı demektir.
    bool isCurrentlyPressed = _pressedButtonCommand == command;
    Color currentButtonColor =
        isCurrentlyPressed
            ? (pressedColor ??
                defaultColor?.withOpacity(0.7) ??
                Colors.blueGrey[900]!)
            : (defaultColor ?? Colors.blueGrey[700]!);

    return GestureDetector(
      onTapDown: (_) {
        // Parmak butona dokunduğunda.
        _sendData(command); // Ana komutu gönder.
        if (mounted) {
          setState(() {
            // Butonun basılı olduğunu ve renginin değişmesi gerektiğini bildir.
            _pressedButtonCommand = command;
          });
        }
        print("onTapDown: $command");
      },
      onTapUp: (_) {
        // Parmak butondan çekildiğinde.
        _sendData(stopCommand); // Durdurma komutunu gönder.
        if (mounted) {
          setState(() {
            // Butonun artık basılı olmadığını ve renginin normale dönmesi gerektiğini bildir.
            _pressedButtonCommand = null;
          });
        }
        print("onTapUp: (command: $command) -> $stopCommand");
      },
      onTapCancel: () {
        // Dokunma iptal edildiğinde (örn: parmak butondan dışarı kaydırıldığında).
        _sendData(stopCommand); // Durdurma komutunu gönder.
        if (mounted) {
          setState(() {
            _pressedButtonCommand = null;
          });
        }
        print("onTapCancel: (command: $command) -> $stopCommand");
      },
      child: Container(
        constraints: BoxConstraints(minWidth: 85, minHeight: 55),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: currentButtonColor, // Dinamik olarak değişen buton rengi.
          borderRadius: BorderRadius.circular(
            10,
          ), // Köşeleri biraz daha yuvarlak.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            iconWidget,
            SizedBox(width: label.isNotEmpty ? 8 : 0),
            if (label.isNotEmpty)
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Butonlar için varsayılan ve basılı renkleri tanımlayalım.
    final Color defaultButtonColor = Colors.blueGrey[700]!;
    final Color pressedButtonColor =
        Colors.blueGrey[900]!; // Veya daha belirgin bir renk
    final Color stopButtonDefaultColor = Colors.redAccent;
    final Color stopButtonPressedColor = Colors.red[700]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedDevice?.name ?? 'Ehara Bağlan'),
        actions: <Widget>[_buildBluetoothIconButton()],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildConnectionBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        _buildControlButton(
                          icon: Icons.rotate_left,
                          label: 'T.SOL',
                          command: 'T',
                          stopCommand: 'S',
                          defaultColor: defaultButtonColor,
                          pressedColor: pressedButtonColor,
                        ),
                        _buildControlButton(
                          icon: Icons.stop_circle_outlined,
                          label: 'DUR',
                          command: 'S',
                          stopCommand: 'S',
                          defaultColor: stopButtonDefaultColor,
                          pressedColor: stopButtonPressedColor,
                        ),
                        _buildControlButton(
                          icon: Icons.rotate_right,
                          label: 'T.SAĞ',
                          command: 'D',
                          stopCommand: 'S',
                          defaultColor: defaultButtonColor,
                          pressedColor: pressedButtonColor,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildControlButton(
                              icon: Icons.keyboard_arrow_up,
                              label: 'X',
                              command: 'X',
                              stopCommand: 'S',
                              defaultColor: defaultButtonColor,
                              pressedColor: pressedButtonColor,
                            ),
                            SizedBox(height: 10),
                            _buildControlButton(
                              icon: Icons.keyboard_arrow_left,
                              label: 'SOL',
                              command: 'L',
                              stopCommand: 'S',
                              defaultColor: defaultButtonColor,
                              pressedColor: pressedButtonColor,
                            ),
                            SizedBox(height: 10),
                            _buildControlButton(
                              icon: Icons.keyboard_arrow_down,
                              label: 'N',
                              command: 'N',
                              stopCommand: 'S',
                              defaultColor: defaultButtonColor,
                              pressedColor: pressedButtonColor,
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _buildControlButton(
                              icon: Icons.arrow_upward,
                              label: 'İLERİ',
                              command: 'F',
                              stopCommand: 'S',
                              defaultColor: defaultButtonColor,
                              pressedColor: pressedButtonColor,
                            ),
                            SizedBox(height: 60),
                            _buildControlButton(
                              icon: Icons.arrow_downward,
                              label: 'GERİ',
                              command: 'B',
                              stopCommand: 'S',
                              defaultColor: defaultButtonColor,
                              pressedColor: pressedButtonColor,
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildControlButton(
                              icon: Icons.keyboard_arrow_up,
                              label: 'M',
                              command: 'M',
                              mirrorIcon: true,
                              stopCommand: 'S',
                              defaultColor: defaultButtonColor,
                              pressedColor: pressedButtonColor,
                            ),
                            SizedBox(height: 10),
                            _buildControlButton(
                              icon: Icons.keyboard_arrow_right,
                              label: 'SAĞ',
                              command: 'R',
                              stopCommand: 'S',
                              defaultColor: defaultButtonColor,
                              pressedColor: pressedButtonColor,
                            ),
                            SizedBox(height: 10),
                            _buildControlButton(
                              icon: Icons.keyboard_arrow_down,
                              label: 'Y',
                              command: 'Y',
                              mirrorIcon: true,
                              stopCommand: 'S',
                              defaultColor: defaultButtonColor,
                              pressedColor: pressedButtonColor,
                            ),
                          ],
                        ),
                        RotatedBox(
                          quarterTurns: 3,
                          child: SizedBox(
                            width: 150,
                            child: Slider(
                              value: _speed,
                              min: 0,
                              max: 100,
                              divisions: 10,
                              label: _speed.round().toString(),
                              onChanged: (double value) {
                                setState(() {
                                  _speed = value;
                                  // Hız anlık gönderilir, basılı tutma mantığı burada geçerli değil.
                                  // _sendData('V${_speed.round()}'); // İsteğe bağlı
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothIconButton() {
    if (!(_bluetoothState.isEnabled ?? false)) {
      return IconButton(
        icon: Icon(Icons.bluetooth_disabled, color: Colors.grey),
        onPressed: () async {
          bool permissionsGranted = await _requestPermissions();
          if (permissionsGranted) {
            FlutterBluetoothSerial.instance.requestEnable();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Bluetooth işlemleri için gerekli izinler verilmedi.',
                  ),
                ),
              );
            }
          }
        },
      );
    }
    return IconButton(
      icon: Icon(
        isConnected
            ? Icons.bluetooth_connected
            : (_isConnecting ? Icons.bluetooth_searching : Icons.bluetooth),
      ),
      onPressed: () async {
        if (isConnected) {
          _disconnect();
        } else if (_isConnecting) {
        } else {
          bool permissionsGranted = await _requestPermissions();
          if (permissionsGranted) {
            await _showDeviceListDialog();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Cihaz taraması için gerekli izinler verilmedi.',
                  ),
                ),
              );
            }
          }
        }
      },
    );
  }

  Future<void> _showDeviceListDialog() async {
    if (!(_bluetoothState.isEnabled ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Önce Bluetooth\'u açın.')));
      }
      return;
    }

    if (_devicesList.isEmpty && !_isCurrentlyDiscovering) {
      _startDiscovery();
    }

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('Cihaz Seçin'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isCurrentlyDiscovering)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text("Cihazlar aranıyor..."),
                          ],
                        ),
                      ),
                    if (_devicesList.isEmpty && !_isCurrentlyDiscovering)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: Text(
                          "Cihaz bulunamadı. 'Tara' butonuna basın veya bekleyin.",
                        ),
                      ),
                    if (_devicesList.isNotEmpty)
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _devicesList.length,
                          itemBuilder: (context, index) {
                            BluetoothDevice device = _devicesList[index];
                            bool isThisDeviceConnected =
                                isConnected &&
                                _selectedDevice?.address == device.address;
                            return ListTile(
                              title: Text(device.name ?? 'Bilinmeyen Cihaz'),
                              subtitle: Text(device.address),
                              trailing:
                                  isThisDeviceConnected
                                      ? Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      )
                                      : null,
                              onTap: () {
                                if (isThisDeviceConnected) return;
                                Navigator.of(context).pop();
                                _connectToDevice(device);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(_isCurrentlyDiscovering ? 'Durdur' : 'Tara'),
                  onPressed: () async {
                    if (_isCurrentlyDiscovering) {
                      await _bluetooth.cancelDiscovery();
                    } else {
                      bool permissionsGranted = await _requestPermissions();
                      if (permissionsGranted) {
                        _startDiscovery();
                      } else {
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Tarama için gerekli izinler alınamadı.',
                              ),
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
                TextButton(
                  child: Text('Kapat'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}
