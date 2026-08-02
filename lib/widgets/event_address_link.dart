import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class EventMapLauncher {
  static Future<bool> open(
    Map<String, dynamic> event, {
    String? address,
  }) async {
    final latitude = _asDouble(event['latitude']);
    final longitude = _asDouble(event['longitude']);
    final fullAddress = (address ?? buildAddress(event)).trim();

    if ((latitude == null || longitude == null) && fullAddress.isEmpty) {
      return false;
    }

    final destination = latitude != null && longitude != null
        ? '$latitude,$longitude'
        : fullAddress;
    final encodedDestination = Uri.encodeComponent(destination);
    final candidates = <Uri>[];

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      candidates.add(Uri.parse('google.navigation:q=$encodedDestination'));
      candidates.add(Uri.parse('geo:0,0?q=$encodedDestination'));
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      candidates.add(
        Uri.parse(
          'comgooglemaps://?daddr=$encodedDestination&directionsmode=driving',
        ),
      );
      candidates.add(
        Uri.parse('https://maps.apple.com/?daddr=$encodedDestination'),
      );
    }

    candidates.add(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$encodedDestination',
      ),
    );

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Tenta o próximo aplicativo e termina no navegador.
      }
    }
    return false;
  }

  static String buildAddress(Map<String, dynamic> event) {
    final street = (event['street'] ?? '').toString().trim();
    final number = (event['street_number'] ?? '').toString().trim();
    final neighborhood = (event['neighborhood'] ?? '').toString().trim();
    final city = (event['city'] ?? '').toString().trim();
    final state = (event['state'] ?? '').toString().trim();
    final cep = (event['cep'] ?? '').toString().trim();

    return [
      '$street${number.isNotEmpty ? ', $number' : ''}'.trim(),
      neighborhood,
      '$city${state.isNotEmpty ? ' - $state' : ''}'.trim(),
      cep,
    ].where((part) => part.isNotEmpty).join(', ');
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }
}

class EventAddressLink extends StatelessWidget {
  const EventAddressLink({
    super.key,
    required this.event,
    this.address,
    this.style,
    this.iconColor,
    this.iconSize = 16,
    this.maxLines = 2,
  });

  final Map<String, dynamic> event;
  final String? address;
  final TextStyle? style;
  final Color? iconColor;
  final double iconSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final label = (address ?? EventMapLauncher.buildAddress(event)).trim();
    if (label.isEmpty) return const SizedBox.shrink();

    final effectiveColor = iconColor ?? style?.color ?? Colors.blueGrey;
    return Semantics(
      button: true,
      label: 'Abrir endereço no GPS: $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final opened = await EventMapLauncher.open(event, address: label);
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Não foi possível abrir o aplicativo de mapas.'),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(Icons.location_on, size: iconSize, color: effectiveColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: (style ?? const TextStyle()).copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: effectiveColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.directions_outlined,
                size: iconSize + 2,
                color: effectiveColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
