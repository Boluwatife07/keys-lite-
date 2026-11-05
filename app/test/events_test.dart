import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/features/events/event_common.dart';
import 'package:keys_lite/features/events/event_detail.dart';
import 'package:keys_lite/features/events/event_form.dart';
import 'package:keys_lite/features/events/events_tab.dart';
import 'package:keys_lite/widgets/widgets.dart';
import 'harness.dart';

Map<String, dynamic> person(String id, String name) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': null};

Map<String, dynamic> card(String id, String title, {String status = 'live', int going = 0, bool soldOut = false, int? capacity}) => {
      'id': id, 'title': title, 'category': 'residential', 'clubId': null, 'clubName': null, 'audience': 'all',
      'startAt': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
      'endAt': DateTime.now().add(const Duration(days: 3, hours: 2)).toUtc().toIso8601String(),
      'format': 'physical', 'locationName': '1 Maple Road', 'locationAddress': '1 Maple Road, London', 'platform': null, 'cover': null,
      'tags': ['Social'], 'price': 'Free', 'going': going, 'capacity': capacity, 'soldOut': soldOut, 'status': status, 'saved': false, 'rating': null, 'isMine': false,
    };

Map<String, dynamic> detail(Map<String, dynamic> c, {String? role, Map<String, dynamic>? ticket, bool canGet = true, bool volunteers = false, String? volunteerState, List problems = const []}) => {
      ...c,
      'description': 'Come along and meet your neighbours.', 'media': [], 'lat': 51.5, 'lng': -0.1, 'placeId': 'p1', 'platformKey': null,
      'link': null, 'meetingId': null, 'meetingPassword': null, 'lineup': [{'id': 'g1', 'name': 'Brian Davis', 'title': 'DJ', 'photoUrl': null}],
      'hosts': [{'id': null, 'person': person('u2', 'Ajani Kimath'), 'name': 'Ajani Kimath', 'role': 'Host', 'external': false, 'status': 'accepted'}],
      'attendingPreview': [], 'acceptVolunteers': volunteers, 'volunteerCap': 2, 'volunteers': [], 'volunteerState': volunteerState,
      'myRole': role, 'myTicket': ticket, 'canGetTicket': canGet, 'verified': true, 'canEdit': role == 'host', 'canScan': role == 'host',
      'chatId': role == null ? null : 'chat1', 'launchProblems': problems, 'cancelReason': null, 'ratings': null, 'canRate': false, 'myRating': null,
      'youMightAlsoLike': [], 'shareLink': 'https://keys.app/event/${c['id']}', 'shareText': "I'm attending the ${c['title']}, and I think you'd really enjoy it. You should come along!",
      'createdAt': '2026-11-01T10:00:00Z',
    };

Map<String, dynamic> ticket({String status = 'active'}) => {
      'id': 't1', 'eventId': 'e1', 'eventTitle': 'Quiz night',
      'startAt': '2026-11-20T18:00:00Z', 'endAt': '2026-11-20T21:00:00Z', 'format': 'physical', 'locationName': '1 Maple Road', 'locationAddress': '',
      'platform': null, 'link': null, 'meetingId': null, 'meetingPassword': null, 'qr': status == 'active' ? 'KEYS-abc' : null, 'seat': status == 'active' ? '001' : null,
      'price': 'Free', 'status': status, 'checkedInAt': null, 'holder': person('u1', 'Amy Duncan'), 'shareLink': status == 'active' ? 'https://keys.app/ticket/t1' : null, 'createdAt': '2026-11-05T10:00:00Z',
    };

Future<void> reveal(WidgetTester t, String text) async {
  await t.scrollUntilVisible(find.text(text), 300, scrollable: find.byType(Scrollable).first);
  await t.ensureVisible(find.text(text));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('EVT-01.4 empty Discover with templates and tag chips', (t) async {
    final h = Harness();
    h.fake.on('GET /events/discover', (_, _) => {'trending': [], 'tags': ['All', 'Music', 'Culture'], 'happeningSoon': [], 'templates': []});
    h.fake.on('GET /events/templates', (_, _) => {'templates': [{'id': 'wine', 'name': 'Wine tasting', 'category': 'residential', 'image': 'template_wine.jpg', 'data': {'description': 'Join fellow wine lovers'}, 'personal': false}], 'personal': []});
    h.fake.on('GET /events/cancelled-popups', (_, _) => {'popups': []});
    h.fake.on('GET /events/rating-prompts', (_, _) => {'prompts': []});
    await h.pump(t, const Scaffold(body: EventsTab()));
    expect(find.text('No events yet'), findsOneWidget);
    expect(find.text('Discover new events hosted by other residents. Click on the + button to create an event.'), findsOneWidget);
    expect(find.text('Wine tasting template'), findsOneWidget);
    expect(find.text('Use template'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Event calendar →'), findsOneWidget);
  });

  testWidgets('EVT-25.1 cancelled pop-up shows once and is marked seen', (t) async {
    final h = Harness();
    h.fake.on('GET /events/discover', (_, _) => {'trending': [], 'tags': ['All'], 'happeningSoon': [], 'templates': []});
    h.fake.on('GET /events/templates', (_, _) => {'templates': [], 'personal': []});
    h.fake.on('GET /events/cancelled-popups', (_, _) => {'popups': [{'ticketId': 't9', 'eventId': 'e9', 'title': 'Event cancelled', 'message': "We're sorry, Picnic has been cancelled by the host."}]});
    h.fake.on('POST /tickets/t9/cancel-seen', (_, _) => {'ok': true});
    h.fake.on('GET /events/rating-prompts', (_, _) => {'prompts': []});
    await h.pump(t, const Scaffold(body: EventsTab()));
    expect(find.text("We're sorry, Picnic has been cancelled by the host."), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(h.fake.called('POST /tickets/t9/cancel-seen'), isTrue);
  });

  testWidgets('EVT-04 category sheet: administrative needs the committee', (t) async {
    final h = Harness();
    h.fake.on('GET /events/discover', (_, _) => {'trending': [], 'tags': ['All'], 'happeningSoon': [], 'templates': []});
    h.fake.on('GET /events/templates', (_, _) => {'templates': [], 'personal': []});
    h.fake.on('GET /events/cancelled-popups', (_, _) => {'popups': []});
    h.fake.on('GET /events/rating-prompts', (_, _) => {'prompts': []});
    h.fake.on('GET /events/create-check', (_, q) => q['category'] == 'administrative'
        ? {'ok': false, 'code': 'NOT_COMMITTEE', 'message': 'To create an administrative event, you must be a member of the committee board. Would you be interested in applying for membership?', 'boardFull': false}
        : {'ok': true, 'clubs': []});
    await h.pump(t, const Scaffold(body: EventsTab()));
    await t.tap(find.byTooltip('Create event'));
    await t.pumpAndSettle();
    expect(find.text('Perfect for casual neighbourhood events.\n•  Host single-day gatherings'), findsOneWidget);
    expect(find.textContaining('£'), findsNothing); // money lines are later phase
    expect(buttonEnabled(t, 'Next'), isFalse);
    await t.tap(find.text('Administrative'));
    await t.pumpAndSettle();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.textContaining('you must be a member of the committee board'), findsOneWidget);
    expect(find.text('Apply for membership'), findsOneWidget);
  });

  testWidgets('EVT-05 form: launch stays off until the required fields are set; save draft works with a title', (t) async {
    final h = Harness();
    h.fake.on('POST /events', (b, _) => {'event': {...detail(card('e1', b['title'], status: 'draft'), role: 'host'), 'chatId': 'chat1'}, 'title': 'Event saved as a draft', 'message': 'You can now plan with your team in the group chat and make any changes until your event is ready to go live.'});
    await h.pump(t, const EventFormScreen(category: 'residential'));
    expect(find.text('Residential'), findsOneWidget);
    expect(find.text('Everyone in this community'), findsOneWidget);
    expect(find.text('Add day'), findsNothing);
    await reveal(t, 'Save event');
    expect(buttonEnabled(t, 'Launch event'), isFalse);
    expect(buttonEnabled(t, 'Save event'), isFalse);
    await t.scrollUntilVisible(find.widgetWithText(TextField, 'Enter event title'), -300, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.widgetWithText(TextField, 'Enter event title'), 'Street party');
    await t.pumpAndSettle();
    expect(find.text('12/60'), findsOneWidget);
    await reveal(t, 'Save event');
    expect(buttonEnabled(t, 'Save event'), isTrue);
    expect(buttonEnabled(t, 'Launch event'), isFalse);
    // Capacity minimum.
    await t.enterText(find.widgetWithText(TextField, 'How many people can attend?'), '5');
    await t.pumpAndSettle();
    expect(find.text('Minimum of 10'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'How many people can attend?'), '');
    await t.pumpAndSettle();
    // Tags: at most 3.
    for (final tag in ['Music', 'Culture', 'Networking']) {
      await reveal(t, tag);
      await t.tap(find.text(tag));
      await t.pumpAndSettle();
    }
    await reveal(t, 'Fashion');
    await t.tap(find.text('Fashion'));
    await t.pump();
    expect(find.text('You can add a maximum of 3 tags'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await reveal(t, 'Save event');
    t.widget<KeysButton>(find.widgetWithText(KeysButton, 'Save event')).onPressed!();
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /events')['tags'], ['Music', 'Culture', 'Networking']);
    expect(find.text('Event saved as a draft'), findsOneWidget);
    expect(find.text('Enter group chat'), findsOneWidget);
    expect(find.text('Preview event'), findsOneWidget);
  });

  testWidgets('EVT-18 / EVT-19 event page and getting a ticket', (t) async {
    final h = Harness();
    var got = false;
    h.fake.on('GET /events/e1', (_, _) => {'event': detail(card('e1', 'Quiz night', going: got ? 1 : 0), ticket: got ? ticket() : null, canGet: !got)});
    h.fake.on('POST /events/e1/tickets', (_, _) {
      got = true;
      return {'ticket': ticket(), 'title': "You're going", 'message': 'Congratulations, your ticket has been booked successfully'};
    });
    h.fake.on('GET /tickets/t1', (_, _) => {'ticket': ticket()});
    await h.pump(t, const EventDetailScreen(id: 'e1'));
    expect(find.text('Quiz night'), findsOneWidget);
    expect(find.text('Event details'), findsOneWidget);
    expect(find.text('Brian Davis'), findsOneWidget);
    await t.tap(find.widgetWithText(KeysButton, 'Get ticket'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(KeysButton, 'Get ticket').last);
    await t.pumpAndSettle();
    expect(find.text("You're going"), findsOneWidget);
    expect(find.text('Congratulations, your ticket has been booked successfully'), findsOneWidget);
    await t.tap(find.text('View ticket').last);
    await t.pumpAndSettle();
    expect(h.location, '/tickets/t1');
  });

  testWidgets('EVT-19.3 sold out; EVT-19.4 unverified gets the verify sheet', (t) async {
    final h = Harness();
    h.fake.on('GET /events/e1', (_, _) => {'event': detail(card('e1', 'Gig', soldOut: true, going: 10, capacity: 10), canGet: false)});
    await h.pump(t, const EventDetailScreen(id: 'e1'));
    expect(find.text('Sold out'), findsWidgets);
    expect(buttonEnabled(t, 'Sold out'), isFalse);
  });

  testWidgets('EVT-22 volunteering then the planning chat', (t) async {
    final h = Harness();
    h.fake.on('GET /events/e1', (_, _) => {'event': detail(card('e1', 'Clean up'), volunteers: true, volunteerState: 'open')});
    h.fake.on('POST /events/e1/volunteer', (_, _) => {'title': 'Thanks for volunteering!', 'message': "You've been added to the planning group chat for this event.", 'chatId': 'chat1'});
    await h.pump(t, const EventDetailScreen(id: 'e1'));
    await reveal(t, 'Apply as volunteer');
    await t.tap(find.text('Apply as volunteer'));
    await t.pumpAndSettle();
    expect(find.text('Volunteer for this event'), findsOneWidget);
    await t.tap(find.text('Volunteer'));
    await t.pumpAndSettle();
    expect(find.text('Thanks for volunteering!'), findsOneWidget);
    expect(find.text('Go to group chat'), findsOneWidget);
  });

  testWidgets('EVT-14 host cancels with a reason; Other needs text', (t) async {
    final h = Harness();
    h.fake.on('GET /events/e1', (_, _) => {'event': detail(card('e1', 'Picnic'), role: 'host')});
    h.fake.on('POST /events/e1/cancel', (_, _) => {'message': 'Event canceled'});
    await h.pump(t, const EventDetailScreen(id: 'e1'));
    await t.tap(find.byTooltip('Event options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel event'));
    await t.pumpAndSettle();
    expect(find.text('Tell us why you are canceling this event'), findsOneWidget);
    await t.tap(find.text('Other (please specify)'));
    await t.pumpAndSettle();
    expect(buttonEnabled(t, 'Continue'), isFalse);
    await t.tap(find.text('Technical issue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Once canceled, attendees will be notified. This action cannot be undone. Are you sure you want to cancel?'), findsOneWidget);
    await t.tap(find.text('Yes, cancel'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /events/e1/cancel')['reason'], 'Technical issue');
    expect(find.text('Event canceled'), findsOneWidget);
  });

  testWidgets('EVT-15 co-host invitation: accept', (t) async {
    final h = Harness();
    h.fake.on('GET /events/e1', (_, _) => {'event': detail(card('e1', 'Fair'), role: 'cohost_invited')});
    h.fake.on('POST /events/e1/cohost/accept', (_, _) => {'message': 'You are now a co-host of this event.'});
    await h.pump(t, const EventDetailScreen(id: 'e1'));
    expect(find.text('You have been added as a co-host!'), findsOneWidget);
    await t.tap(find.text('Accept invitation'));
    await t.pumpAndSettle();
    expect(h.fake.called('POST /events/e1/cohost/accept'), isTrue);
  });

  testWidgets('EVT-20 ticket: QR, seat, Free, download PDF, cancel removes QR', (t) async {
    final h = Harness();
    h.fake.on('GET /tickets/t1', (_, _) => {'ticket': ticket()});
    h.fake.on('POST /tickets/t1/cancel', (_, _) => {'ticket': ticket(status: 'cancelled'), 'title': 'TICKET CANCELLED', 'message': 'Your ticket has been cancelled.'});
    await h.pump(t, const TicketScreen(id: 't1'));
    expect(find.text('001'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Show qrcode and scan upon arrival to event'), findsOneWidget);
    await t.tap(find.text('Download'));
    await t.pumpAndSettle();
    expect(h.sharer.files, ['ticket-001.pdf']);
    await t.tap(find.text('Cancel ticket').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel ticket').last);
    await t.pumpAndSettle();
    expect(find.text('TICKET CANCELLED'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('EVT-23 scanning: valid then used', (t) async {
    final h = Harness();
    var n = 0;
    h.fake.on('GET /events/e1/checkins', (_, _) => {'checkedIn': 0, 'total': 2});
    h.fake.on('POST /events/e1/scan', (b, _) => n++ == 0
        ? {'result': 'valid', 'title': 'Let them in!', 'message': 'Valid ticket.', 'ticket': {'seat': '001', 'holder': person('u3', 'Ashley White')}, 'checkedInLabel': 'Checked in 9:04am', 'checkedIn': 1, 'total': 2}
        : {'result': 'used', 'title': 'Ticket void!', 'message': 'This ticket has already been checked in earlier.', 'ticket': {'seat': '001', 'holder': person('u3', 'Ashley White')}, 'checkedIn': 1, 'total': 2});
    await h.pump(t, const ScanScreen(id: 'e1'));
    expect(find.text('0 / 2 checked in'), findsOneWidget);
    expect(find.text('Point the camera at the attendees ticket QR code'), findsOneWidget);
    Future<void> scan() async {
      await t.tap(find.text('Enter code instead'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'KEYS-abc');
      await t.tap(find.text('Check'));
      await t.pumpAndSettle();
    }

    await scan();
    expect(find.text('Let them in!'), findsOneWidget);
    expect(find.text('Ashley White'), findsOneWidget);
    expect(find.text('1 / 2 checked in'), findsOneWidget);
    await t.tap(find.text('Scan next'));
    await t.pumpAndSettle();
    await scan();
    expect(find.text('Ticket void!'), findsOneWidget);
  });

  testWidgets('EVT-24 rating: Submit needs stars; feedback up to 400', (t) async {
    final h = Harness();
    h.fake.on('POST /events/e1/rating', (b, _) => {'title': 'Rating submitted', 'message': 'Thanks for sharing your feedback!'});
    await h.pump(t, Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showRatingSheet(c, EventItem(card('e1', 'Bake off'))), child: const Text('open')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('How was your experience?'), findsOneWidget);
    expect(buttonEnabled(t, 'Submit'), isFalse);
    await t.tap(find.byTooltip('4 stars'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Lovely');
    await t.tap(find.text('Submit'));
    await t.pumpAndSettle();
    expect(h.fake.lastBody('POST /events/e1/rating'), {'stars': 4, 'text': 'Lovely'});
    expect(find.text('Rating submitted. Thanks for sharing your feedback!'), findsOneWidget);
  });

  testWidgets('EVT-16 attendees empty state offers sharing', (t) async {
    final h = Harness();
    h.fake.on('GET /events/e1/attendees', (_, _) => {'taken': 0, 'capacity': 50, 'checkedIn': 0, 'recent': [], 'all': [], 'canDownload': false});
    await h.pump(t, const AttendeesScreen(id: 'e1'));
    expect(find.text('No tickets sold yet'), findsOneWidget);
    expect(find.text('Your ticket sales will appear here once people start booking.'), findsOneWidget);
    expect(find.text('Share your event'), findsOneWidget);
    expect(find.textContaining('Download'), findsNothing);
  });

  testWidgets('EVT-02 My events empty states per tab', (t) async {
    final h = Harness();
    h.fake.on('GET /events/discover', (_, _) => {'trending': [], 'tags': ['All'], 'happeningSoon': [], 'templates': []});
    h.fake.on('GET /events/templates', (_, _) => {'templates': [], 'personal': []});
    h.fake.on('GET /events/cancelled-popups', (_, _) => {'popups': []});
    h.fake.on('GET /events/rating-prompts', (_, _) => {'prompts': []});
    h.fake.on('GET /events/mine', (_, _) => {'events': []});
    await h.pump(t, const Scaffold(body: EventsTab()));
    await t.tap(find.text('My events'));
    await t.pumpAndSettle();
    expect(find.text("Events you've gotten tickets for would be shown here."), findsOneWidget);
    await t.tap(find.text('Hosting'));
    await t.pumpAndSettle();
    expect(find.text('Events you create will appear here. Click on the + button to create an event.'), findsOneWidget);
    await t.tap(find.text('Cancelled'));
    await t.pumpAndSettle();
    expect(find.text('Events you have cancelled would be shown here.'), findsOneWidget);
    await t.tap(find.text('Saved'));
    await t.pumpAndSettle();
    expect(find.text('Events you save would appear here.'), findsOneWidget);
  });

  testWidgets('API errors surface on the form', (t) async {
    final h = Harness();
    h.fake.on('POST /events', (_, _) => ApiException(400, 'MEDIA_INVALID', 'One of the files could not be found. Please add it again.'));
    await h.pump(t, const EventFormScreen(category: 'residential'));
    await t.enterText(find.widgetWithText(TextField, 'Enter event title'), 'Party');
    await t.pumpAndSettle();
    await reveal(t, 'Save event');
    await t.tap(find.text('Save event'));
    await t.pumpAndSettle();
    expect(find.text('One of the files could not be found. Please add it again.'), findsOneWidget);
  });
}
