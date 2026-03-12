import 'element_shape.dart';

/// Types of non-bookable venue elements.
enum ElementType {
  stage,
  bar,
  entrance,
  restroom,
  label;

  static ElementType fromString(String? value) {
    return ElementType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ElementType.label,
    );
  }

  String get displayLabel => switch (this) {
    ElementType.stage => 'Stage',
    ElementType.bar => 'Bar',
    ElementType.entrance => 'Entrance',
    ElementType.restroom => 'Restroom',
    ElementType.label => 'Label',
  };
}

/// A non-bookable element on the venue canvas (stage, bar, entrance, etc.).
class VenueElement {
  final String id;
  final ElementType type;
  final String label;
  final ElementShape shape;

  const VenueElement({
    required this.id,
    required this.type,
    required this.label,
    required this.shape,
  });

  VenueElement copyWith({
    String? id,
    ElementType? type,
    String? label,
    ElementShape? shape,
  }) {
    return VenueElement(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      shape: shape ?? this.shape,
    );
  }

  factory VenueElement.fromJson(Map<String, dynamic> json) {
    return VenueElement(
      id: json['id'] as String,
      type: ElementType.fromString(json['type'] as String?),
      label: json['label'] as String? ?? '',
      shape: ElementShape.fromJson(json['shape'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'label': label,
      'shape': shape.toJson(),
    };
  }
}
