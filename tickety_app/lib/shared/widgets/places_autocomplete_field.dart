import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization/localization.dart';
import '../../core/services/google_places_service.dart';

/// A text field with Google Places autocomplete suggestions.
///
/// Shows a dropdown of predictions as the user types, and calls
/// [onPlaceSelected] with full [PlaceDetails] when a prediction is chosen.
class PlacesAutocompleteField extends StatefulWidget {
  /// Called when a place is selected from the dropdown.
  final ValueChanged<PlaceDetails> onPlaceSelected;

  /// Called when the field is cleared.
  final VoidCallback? onCleared;

  /// Initial display text (e.g. for editing existing events).
  final String? initialValue;

  const PlacesAutocompleteField({
    super.key,
    required this.onPlaceSelected,
    this.onCleared,
    this.initialValue,
  });

  @override
  State<PlacesAutocompleteField> createState() =>
      _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _placesService = GooglePlacesService();

  List<PlacePrediction> _predictions = [];
  bool _isLoading = false;
  bool _hasSelection = false;
  Timer? _debounce;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _hasSelection = widget.initialValue != null && widget.initialValue!.isNotEmpty;
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _placesService.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    }
  }

  void _onChanged(String value) {
    if (_hasSelection) {
      // User is editing after a selection — reset
      _hasSelection = false;
      widget.onCleared?.call();
    }

    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _removeOverlay();
      setState(() => _predictions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchPredictions(value);
    });
  }

  Future<void> _fetchPredictions(String input) async {
    setState(() => _isLoading = true);
    try {
      final results = await _placesService.getAutocompletePredictions(input);
      if (mounted) {
        setState(() {
          _predictions = results;
          _isLoading = false;
        });
        if (results.isNotEmpty) {
          _showOverlay();
        } else {
          _removeOverlay();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onPredictionSelected(PlacePrediction prediction) async {
    _removeOverlay();
    _controller.text = prediction.description;
    setState(() {
      _predictions = [];
      _isLoading = true;
      _hasSelection = true;
    });

    try {
      final details = await _placesService.getPlaceDetails(prediction.placeId);
      if (mounted && details != null) {
        setState(() => _isLoading = false);
        widget.onPlaceSelected(details);
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clear() {
    _controller.clear();
    _removeOverlay();
    setState(() {
      _predictions = [];
      _hasSelection = false;
    });
    widget.onCleared?.call();
    _focusNode.requestFocus();
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 4),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: colorScheme.surfaceContainerHigh,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _predictions.map((prediction) {
                    return InkWell(
                      onTap: () => _onPredictionSelected(prediction),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    prediction.mainText,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (prediction.secondaryText.isNotEmpty)
                                    Text(
                                      prediction.secondaryText,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        decoration: InputDecoration(
          labelText: L.tr('location'),
          hintText: L.tr('search_venue_or_address'),
          prefixIcon: const Icon(Icons.location_on_outlined),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clear,
                    )
                  : null,
          border: const OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.words,
      ),
    );
  }
}
