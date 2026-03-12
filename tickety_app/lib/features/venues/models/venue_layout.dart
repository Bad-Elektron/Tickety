import 'venue_element.dart';
import 'venue_section.dart';

/// The complete layout of a venue — sections + decorative elements.
class VenueLayout {
  final List<VenueSection> sections;
  final List<VenueElement> elements;
  final int gridSize;
  final int version;

  const VenueLayout({
    this.sections = const [],
    this.elements = const [],
    this.gridSize = 12,
    this.version = 1,
  });

  /// Total capacity across all sections.
  int get totalCapacity =>
      sections.fold(0, (sum, section) => sum + section.seatCount);

  VenueLayout copyWith({
    List<VenueSection>? sections,
    List<VenueElement>? elements,
    int? gridSize,
    int? version,
  }) {
    return VenueLayout(
      sections: sections ?? this.sections,
      elements: elements ?? this.elements,
      gridSize: gridSize ?? this.gridSize,
      version: version ?? this.version,
    );
  }

  factory VenueLayout.fromJson(Map<String, dynamic> json) {
    final sectionsList = json['sections'] as List<dynamic>? ?? [];
    final elementsList = json['elements'] as List<dynamic>? ?? [];
    return VenueLayout(
      sections: sectionsList
          .map((s) => VenueSection.fromJson(s as Map<String, dynamic>))
          .toList(),
      elements: elementsList
          .map((e) => VenueElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      gridSize: json['gridSize'] as int? ?? 12,
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sections': sections.map((s) => s.toJson()).toList(),
      'elements': elements.map((e) => e.toJson()).toList(),
      'gridSize': gridSize,
      'version': version,
    };
  }
}
