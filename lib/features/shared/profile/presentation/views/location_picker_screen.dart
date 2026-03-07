import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class MapLocationResult {
  final double latitude;
  final double longitude;
  final String address;
  final String? countryCode;

  const MapLocationResult({
    required this.latitude,
    required this.longitude,
    required this.address,
    this.countryCode,
  });
}

class LocationPickerScreen extends StatefulWidget {
  final String apiKey;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  const LocationPickerScreen({
    super.key,
    required this.apiKey,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _defaultLat = -33.4489; // Santiago
  static const _defaultLng = -70.6693;

  late LatLng _selected;
  late final TextEditingController _addressController;
  late final TextEditingController _searchController;
  GoogleMapController? _controller;
  bool _isLocating = false;
  bool _isResolvingAddress = false;
  String? _selectedCountryCode;
  Timer? _resolveDebounce;
  int _resolveSeq = 0;
  final Map<String, ({String address, String? countryCode})> _addressCache = {};

  @override
  void initState() {
    super.initState();
    _selected = LatLng(
      widget.initialLatitude ?? _defaultLat,
      widget.initialLongitude ?? _defaultLng,
    );
    _addressController = TextEditingController(text: widget.initialAddress ?? '');
    _searchController = TextEditingController();

    // Intentar centrar en ubicación del usuario al abrir
    _ensureUserLocation();
  }

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    _addressController.dispose();
    _searchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onTap(LatLng pos) {
    setState(() {
      _selected = pos;
      _addressController.text = _formatLatLng(pos);
    });

    _resolveDebounced(pos);
  }

  void _resolveDebounced(LatLng pos) {
    _resolveDebounce?.cancel();
    _resolveDebounce = Timer(const Duration(milliseconds: 350), () {
      _resolveAddressFromLatLng(pos);
    });
  }

  Future<void> _resolveAddressFromLatLng(LatLng pos) async {
    if (widget.apiKey.trim().isEmpty) return;

    final cacheKey =
        '${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}';
    final cached = _addressCache[cacheKey];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _selectedCountryCode = cached.countryCode;
        if (_addressController.text.trim().startsWith('Lat:')) {
          _addressController.text = cached.address;
        }
      });
      return;
    }

    final seq = ++_resolveSeq;

    if (mounted) {
      setState(() => _isResolvingAddress = true);
    }
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}'
        '&key=${widget.apiKey}',
      );

      Future<http.Response> getRequest() {
        return http.get(uri).timeout(const Duration(seconds: 8));
      }

      http.Response res;
      try {
        res = await getRequest();
      } on TimeoutException {
        res = await getRequest();
      }
      if (res.statusCode != 200) return;

      final decoded = json.decode(res.body);
      if (decoded is! Map<String, dynamic>) return;

      String? compoundPlusCode;
      final plusCode = decoded['plus_code'];
      if (plusCode is Map<String, dynamic>) {
        final compound = plusCode['compound_code'];
        if (compound is String && compound.trim().isNotEmpty) {
          compoundPlusCode = compound.trim();
        }
      }

      final results = decoded['results'];
      if (results is! List || results.isEmpty) return;

      final first = results.first;
      if (first is! Map<String, dynamic>) return;

      String? countryCode;
      final addressComponents = first['address_components'];
      if (addressComponents is List) {
        for (final c in addressComponents) {
          if (c is! Map<String, dynamic>) continue;
          final types = c['types'];
          final shortName = c['short_name'];
          if (types is List && types.contains('country')) {
            if (shortName is String && shortName.trim().isNotEmpty) {
              countryCode = shortName.trim().toUpperCase();
              break;
            }
          }
        }
      }

      final formatted = first['formatted_address'];
      if (formatted is! String || formatted.trim().isEmpty) return;

      final resolved = _sanitizeAddress(
        compoundPlusCode != null
            ? '$compoundPlusCode, ${formatted.trim()}'
            : formatted.trim(),
      );
      if (seq != _resolveSeq) return;
      if (!mounted) return;
      setState(() {
        _selectedCountryCode = countryCode;
        _addressCache[cacheKey] = (address: resolved, countryCode: countryCode);
        if (compoundPlusCode != null) {
          _addressController.text = resolved;
          return;
        }

        // Avoid overwriting if user already selected a place from autocomplete.
        // Only replace if it's still showing the lat/lng placeholder.
        if (_addressController.text.trim().startsWith('Lat:')) {
          _addressController.text = resolved;
        }
      });
    } catch (_) {
      // Keep fallback text
    } finally {
      if (mounted && seq == _resolveSeq) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  void _onConfirm() {
    final addressText = _addressController.text.trim();
    final resolvedAddress = addressText.isNotEmpty
        ? addressText
        : _formatLatLng(_selected);

    Navigator.of(context).pop(
      MapLocationResult(
        latitude: _selected.latitude,
        longitude: _selected.longitude,
        address: _sanitizeAddress(resolvedAddress),
        countryCode: _selectedCountryCode,
      ),
    );
  }

  Future<void> _onConfirmAsync() async {
    if (_isResolvingAddress) return;

    // If user tapped the map and the placeholder is still shown, try to resolve
    // once before returning.
    if (_addressController.text.trim().startsWith('Lat:')) {
      await _resolveAddressFromLatLng(_selected);
    }

    _onConfirm();
  }

  String _sanitizeAddress(String value) {
    final trimmed = value.trim();

    // Avoid dangling commas/spaces.
    return trimmed.replaceAll(RegExp(r'[\s,]+$'), '').trim();
  }

  String _formatLatLng(LatLng pos) =>
      'Lat: ${pos.latitude.toStringAsFixed(6)}, Lng: ${pos.longitude.toStringAsFixed(6)}';

  Future<void> _ensureUserLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final userLatLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _selected = userLatLng;
        if (_addressController.text.trim().isEmpty) {
          _addressController.text = _formatLatLng(userLatLng);
        }
      });
      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: userLatLng, zoom: 15),
        ),
      );
    } catch (_) {
      // Silenciar errores; fallback al default
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecciona ubicación'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: GooglePlaceAutoCompleteTextField(
              textEditingController: _searchController,
              googleAPIKey: widget.apiKey,
              inputDecoration: InputDecoration(
                hintText: 'Buscar lugar o local...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              itemClick: (Prediction p) {
                _searchController.text = p.description ?? '';
                final desc = p.description;
                _addressController.text =
                    desc != null ? _sanitizeAddress(desc) : _addressController.text;
              },
              isLatLngRequired: true,
              getPlaceDetailWithLatLng: (Prediction p) async {
                if (p.lat != null && p.lng != null) {
                  final latLng = LatLng(double.parse(p.lat!), double.parse(p.lng!));
                  setState(() {
                    _selected = latLng;
                    final desc = p.description;
                    _addressController.text = desc != null
                        ? _sanitizeAddress(desc)
                        : _formatLatLng(latLng);
                  });
                  await _controller?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(target: latLng, zoom: 16),
                    ),
                  );
                }
              },
              debounceTime: 600,
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _selected,
                zoom: 14,
              ),
              onMapCreated: (c) => _controller = c,
              markers: {
                Marker(
                  markerId: const MarkerId('selected'),
                  position: _selected,
                  draggable: true,
                  onDragEnd: _onTap,
                ),
              },
              onTap: _onTap,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _isResolvingAddress ? null : _onConfirmAsync,
                    child: _isResolvingAddress
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Usar esta ubicación',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
