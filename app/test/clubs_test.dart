import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keys_lite/core/api.dart';
import 'package:keys_lite/features/calendar/calendar.dart';
import 'package:keys_lite/features/clubs/club_detail.dart';
import 'package:keys_lite/features/clubs/club_form.dart';
import 'package:keys_lite/features/clubs/clubs_tab.dart';
import 'package:keys_lite/widgets/widgets.dart';
import 'harness.dart';

Map<String, dynamic> person(String id, String name) => {'id': id, 'name': name, 'firstName': name.split(' ').first, 'photoUrl': null, 'verified': true, 'role': null};

Map<String, dynamic> club(String id, String name, {String? role, bool full = false, String status = 'active', Map<String, dynamic>? transfer}) => {
      'id': id, 'name': name, 'description': 'For fans of the Blues', 'category': 'Sports', 'price': 'Free', 'coverUrl': null,
      'memberCount': 3, 'memberLimit': 10, 'full': full, 'president': person('u2', 'Jules Winnfield'), 'myRole': role, 'isMember': role != null,
      'membersPreview': [], 'membersText': 'Jules, Ella and 1 other are in this club', 'othersText': '+3 others are in this club',
      'status': status, 'closingAt': status == 'closing' ? '2026-11-07T10:00:00Z' : null, 'createdAt': '2026-10-01T10:00:00Z',
      'chatId': role == null ? null : 'chat1', 'muted': false, 'upcomingEvents': 0, 'transfer': transfer,
      'canEdit': role == 'president' || role == 'admin', 'canEditName': role == 'president',
      'shareLink': 'https://keys.app/club/$id', 'shareText': "You've been invited to join the $name Club on Keys.", 'inviteLink': 'https://keys.app/club-invite/$id',
    };

void clubPage(Harness h, Map<String, dynamic> c, {List announcements = const [], bool hidden = false}) {
  h.fake.on('GET /clubs/${c['id']}', (_, _) => {'club': c});
  h.fake.on('GET /clubs/${c['id']}/announcements', (_, _) => {'announcements': announcements, 'membersOnlyHidden': hidden});
  h.fake.on('GET /clubs/${c['id']}/events', (_, _) => {'events': []});
}

void main() {
  testWidgets('CLB-01.2 Home empty: hint and templates', (t) async {
    final h = Harness();
    h.fake.on('GET /clubs/home', (_, _) => {'myClubs': [], 'announcements': [], 'templates': []});
    h.fake.on('GET /clubs/templates', (_, _) => {'templates': [{'id': 'baking', 'label': 'Baking', 'name': 'Sweet Treats', 'category': 'Food & Drink', 'memberLimit': 30, 'image': 'club_baking.jpg', 'description': 'Home bakers'}]});
    await h.pump(t, const Scaffold(body: ClubsTab()));
    expect(find.text('Click on the + button to create a new club or use one of the provided templates below.'), findsOneWidget);
    expect(find.text('Create your club in one click'), findsOneWidget);
    expect(find.text('Baking Club Template'), findsOneWidget);
  });

  testWidgets('CLB-01.4 Discover empty and categories', (t) async {
    final h = Harness();
    h.fake.on('GET /clubs/home', (_, _) => {'myClubs': [], 'announcements': [], 'templates': []});
    h.fake.on('GET /clubs/templates', (_, _) => {'templates': []});
    h.fake.on('GET /clubs/discover', (_, _) => {'categories': ['All', 'Lifestyle', 'Sports'], 'clubs': []});
    await h.pump(t, const Scaffold(body: ClubsTab()));
    await t.tap(find.text('Discover'));
    await t.pumpAndSettle();
    expect(find.text('No Clubs yet'), findsOneWidget);
    expect(find.text('Discover new clubs created other residents. Click on the + button to create a club.'), findsOneWidget);
    expect(find.text('Lifestyle'), findsOneWidget);
  });

  testWidgets('CLB-03.6 unverified residents see the verify sheet instead of the form', (t) async {
    final h = Harness();
    h.fake.on('GET /clubs/home', (_, _) => {'myClubs': [], 'announcements': [], 'templates': []});
    h.fake.on('GET /clubs/templates', (_, _) => {'templates': []});
    await h.pump(t, const Scaffold(body: ClubsTab()), meJson: Harness.me(status: 'unverified'));
    await t.tap(find.byTooltip('Create club'));
    await t.pumpAndSettle();
    expect(find.text('Verify your home address'), findsOneWidget);
  });

  testWidgets('CLB-03 create form: all required; minimum 10; free note; name taken', (t) async {
    final h = Harness();
    h.media.photo = fakePng(1000);
    await h.pump(t, const ClubFormScreen());
    expect(find.text('Free clubs are not eligible for monetization via subscriptions or event ticket sales.'), findsOneWidget);
    expect(buttonEnabled(t, 'Continue'), isFalse);
    await t.enterText(find.widgetWithText(TextField, 'Enter club name'), 'Blues United FC Fans');
    await t.enterText(find.widgetWithText(TextField, 'What is your club about and what should members expect?'), 'For fans');
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Sports').last);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Maximum number of members'), '5');
    await t.pumpAndSettle();
    expect(find.text('Minimum of 10 members'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Maximum number of members'), '20');
    await t.pumpAndSettle();
    expect(buttonEnabled(t, 'Continue'), isFalse); // cover still missing
    await t.scrollUntilVisible(find.text('Upload cover image'), 300, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await t.pumpAndSettle();
    await t.tap(find.text('Upload cover image'));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
    expect(buttonEnabled(t, 'Continue'), isTrue);
  });

  testWidgets('CLB-05 visitor view: Join, members-only prompt; CLB-06.2 full club', (t) async {
    final h = Harness();
    clubPage(h, club('k1', 'Blues United FC Fans'), hidden: true);
    h.fake.on('POST /clubs/k1/join', (_, _) => ApiException(409, 'CLUB_FULL', "Blues United FC Fans has reached its member limit and isn't accepting new members right now. Please check back later.", {'title': 'This club is currently full'}));
    await h.pump(t, const ClubDetailScreen(id: 'k1'));
    expect(find.text('Blues United FC Fans'), findsOneWidget);
    expect(find.text('Jules, Ella and 1 other are in this club'), findsOneWidget);
    expect(find.text('Join Blues United FC Fans'), findsOneWidget);
    expect(find.text('To view messages, see all activities and participate in club events you have to be a member of this club.'), findsOneWidget);
    await t.tap(find.text('Join club'));
    await t.pumpAndSettle();
    expect(find.text('This club is currently full'), findsOneWidget);
  });

  testWidgets('CLB-08 member options: mute, share, report, leave', (t) async {
    final h = Harness();
    clubPage(h, club('k1', 'Blues', role: 'member'));
    h.fake.on('POST /clubs/k1/leave', (_, _) => {'message': 'You exited Blues'});
    await h.pump(t, const ClubDetailScreen(id: 'k1'));
    expect(find.text('Join club'), findsNothing);
    await t.tap(find.byTooltip('Club options'));
    await t.pumpAndSettle();
    for (final o in ['Mute notifications', 'Share', 'Report club', 'Leave club']) {
      expect(find.text(o), findsOneWidget);
    }
    expect(find.text('Delete club'), findsNothing);
    expect(find.text('Edit club details'), findsNothing);
    await t.tap(find.text('Leave club'));
    await t.pumpAndSettle();
    expect(find.text("Are you sure you want to leave Blues? You will no longer have access to this club's content."), findsOneWidget);
    await t.tap(find.text('Leave'));
    await t.pumpAndSettle();
    expect(find.text('You exited Blues'), findsOneWidget);
  });

  testWidgets('CLB-11 / CLB-12 President: transfer status, delete in two steps', (t) async {
    final h = Harness();
    clubPage(h, club('k1', 'Blues', role: 'president', transfer: {'id': 'tr1', 'to': person('u3', 'Ajani Kimath'), 'status': 'Awaiting response', 'forMe': false}));
    h.fake.on('POST /clubs/k1/delete', (_, _) => {'title': 'Club deleted', 'message': 'Your club Blues would be closed permanently in 48hours.'});
    await h.pump(t, const ClubDetailScreen(id: 'k1'));
    expect(find.text('Transfer status'), findsOneWidget);
    expect(find.text('Awaiting response'), findsOneWidget);
    await t.tap(find.byTooltip('Club options'));
    await t.pumpAndSettle();
    expect(find.text('Withdraw ownership offer'), findsOneWidget);
    await t.tap(find.text('Delete club'));
    await t.pumpAndSettle();
    expect(find.text('Delete this club?'), findsOneWidget);
    await t.tap(find.text('Delete anyways'));
    await t.pumpAndSettle();
    expect(find.text('Delete Blues'), findsOneWidget);
    await t.tap(find.widgetWithText(KeysButton, 'Delete'));
    await t.pumpAndSettle();
    expect(find.text('Your club Blues would be closed permanently in 48hours.'), findsOneWidget);
  });

  testWidgets('CLB-11.3 the recipient accepts the ownership offer', (t) async {
    final h = Harness();
    clubPage(h, club('k1', 'Blues', role: 'member', transfer: {'id': 'tr1', 'to': person('u1', 'Amy Duncan'), 'status': 'Awaiting response', 'forMe': true}));
    h.fake.on('POST /club-transfers/tr1/accept', (_, _) => {'message': 'Club ownership transferred.'});
    await h.pump(t, const ClubDetailScreen(id: 'k1'));
    expect(find.text('Club Ownership Transfer'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(find.text('Club ownership transferred.'), findsOneWidget);
  });

  testWidgets('CLB-10 President makes an admin with the confirmation copy', (t) async {
    final h = Harness();
    h.fake.on('GET /clubs/k1/members', (_, _) => {
          'members': [
            {'person': person('u1', 'Amy Duncan'), 'role': 'president', 'roleLabel': 'Club president'},
            {'person': person('u3', 'Ella White'), 'role': 'member', 'roleLabel': 'Member'},
          ],
          'countLabel': '2/10 members',
          'myRole': 'president',
        });
    h.fake.on('POST /clubs/k1/admins/u3', (_, _) => {'message': 'Ella White is now an admin'});
    await h.pump(t, const ClubMembersScreen(id: 'k1'));
    expect(find.text('2/10 members'), findsOneWidget);
    expect(find.text('Club president'), findsOneWidget);
    await t.tap(find.text('Ella White'));
    await t.pumpAndSettle();
    await t.tap(find.text('Make an admin'));
    await t.pumpAndSettle();
    expect(find.text('Are you sure you want to give Ella White admin access? They will be able to remove members, create club events and post club activities'), findsOneWidget);
    await t.tap(find.text('Make admin'));
    await t.pumpAndSettle();
    expect(find.text('Ella White is now an admin'), findsOneWidget);
  });

  testWidgets('CAL-03 month view: empty day copy and nearest schedule', (t) async {
    final h = Harness();
    h.fake.on('GET /calendar', (_, _) => {'items': [], 'today': '2026-11-05'});
    h.fake.on('GET /calendar/nearest', (_, _) => {'item': null});
    await h.pump(t, const CalendarScreen());
    expect(find.text('No schedule yet'), findsOneWidget);
    expect(find.text('You have no schedule to display on this day. Please select another date.'), findsOneWidget);
    expect(find.text('Go to nearest schedule'), findsOneWidget);
  });

  testWidgets('CAL-01.3 events-only calendar copy', (t) async {
    final h = Harness();
    h.fake.on('GET /calendar', (_, q) {
      expect(q['types'], 'event');
      return {'items': [], 'today': '2026-11-05'};
    });
    await h.pump(t, const CalendarScreen(eventsOnly: true));
    expect(find.text('No event yet'), findsOneWidget);
    expect(find.text('There are no events scheduled for this day.'), findsOneWidget);
    expect(find.text('Go to next event'), findsOneWidget);
  });

  testWidgets('CAL-03.2 items list for the selected day with markers', (t) async {
    final h = Harness();
    final now = DateTime.now();
    h.fake.on('GET /calendar', (_, _) => {
          'items': [
            {'type': 'event', 'color': '#1C8C86', 'id': 'e1', 'title': 'Movie night', 'subtitle': '6:00pm - 9:00pm • 1 Maple Road', 'at': now.toUtc().toIso8601String(), 'time': '6:00pm', 'open': {'type': 'event', 'id': 'e1'}},
            {'type': 'update', 'color': '#D92D20', 'id': 'u1', 'title': 'Bins tomorrow', 'subtitle': 'Put them out', 'at': now.toUtc().toIso8601String(), 'time': '9:00am', 'open': {'type': 'update', 'id': 'u1'}},
          ],
          'today': '',
        });
    await h.pump(t, const CalendarScreen());
    expect(find.text('Movie night'), findsOneWidget);
    expect(find.text('Bins tomorrow'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('2 items')), findsOneWidget);
  });

  testWidgets('CAL-02 Home upcoming preview: today tag and +N today', (t) async {
    final h = Harness();
    h.fake.on('GET /calendar/upcoming', (_, _) => {
          'day': '2026-11-05',
          'today': true,
          'more': 2,
          'items': [
            {'type': 'event', 'color': '#1C8C86', 'id': 'e1', 'title': 'Movie night', 'subtitle': '6:00pm', 'at': DateTime.now().toUtc().toIso8601String(), 'time': '6:00pm', 'open': {'type': 'event', 'id': 'e1'}},
          ],
        });
    await h.pump(t, const Scaffold(body: UpcomingPreview()));
    expect(find.text('Movie night'), findsOneWidget);
    expect(find.text('today'), findsOneWidget);
    expect(find.text('+2 today'), findsOneWidget);
    expect(find.text('Calendar →'), findsOneWidget);
  });
}
