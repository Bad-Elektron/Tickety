import '../../events/models/event_model.dart';
import 'external_event.dart';

sealed class FeedItem {
  DateTime get sortDate;
  String get feedTitle;
  String? get feedLocation;
  String? get feedCategory;
}

class NativeEventFeedItem extends FeedItem {
  final EventModel event;

  NativeEventFeedItem(this.event);

  @override
  DateTime get sortDate => event.date;

  @override
  String get feedTitle => event.title;

  @override
  String? get feedLocation => event.getDisplayLocation(hasTicket: false);

  @override
  String? get feedCategory => event.category;
}

class ExternalEventFeedItem extends FeedItem {
  final ExternalEvent event;

  ExternalEventFeedItem(this.event);

  @override
  DateTime get sortDate => event.startDate;

  @override
  String get feedTitle => event.title;

  @override
  String? get feedLocation => event.displayLocation.isNotEmpty ? event.displayLocation : null;

  @override
  String? get feedCategory => event.category;
}
