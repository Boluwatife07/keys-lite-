// CLB-03.1 / CLB-01.3 club categories.
export const CLUB_CATEGORIES = ['Lifestyle', 'Sports', 'Music', 'Food & Drink', 'Creative', 'Gaming', 'Pets', 'Wellness', 'Learning', 'Others'] as const;

// CLB-04.1: eight templates. Descriptions are kept within the 300 character limit (CLB-Q1 default).
export const CLUB_TEMPLATES = [
  { id: 'baking', label: 'Baking', name: 'Sweet Treats', category: 'Food & Drink', memberLimit: 30, image: 'club_baking.jpg',
    description: 'A friendly club for home bakers. Swap recipes, share tips, show off your bakes and meet up for bake-alongs and tasting days. Beginners and seasoned bakers are all welcome.' },
  { id: 'photography', label: 'Photography', name: 'Through the Lens', category: 'Creative', memberLimit: 30, image: 'club_photography.jpg',
    description: 'For anyone who loves taking pictures, on a phone or a camera. Join photo walks around the neighbourhood, share your shots and learn new techniques together.' },
  { id: 'golf', label: 'Golf', name: 'Fairway Friends', category: 'Sports', memberLimit: 20, image: 'club_golf.jpg',
    description: 'Neighbours who enjoy a round of golf. Organise tee times, practise at the range together and welcome players of every handicap.' },
  { id: 'cycling', label: 'Cycling', name: 'Pedal Pals', category: 'Sports', memberLimit: 40, image: 'club_cycling.jpg',
    description: 'Weekend rides, commuter tips and bike maintenance help. Ride at a pace that suits you with neighbours who love being on two wheels.' },
  { id: 'running', label: 'Running', name: 'Run Club', category: 'Sports', memberLimit: 50, image: 'club_running.jpg',
    description: 'Lace up and run with your neighbours. Weekly group runs for all paces, couch-to-5k support and friendly company on the road.' },
  { id: 'gaming', label: 'Gaming', name: 'Game Night', category: 'Gaming', memberLimit: 30, image: 'club_gaming.jpg',
    description: 'Board games, card games and video games. Meet up for game nights, find teammates online and share your latest favourites.' },
  { id: 'dog-owners', label: 'Dog Owners', name: 'Paws & Friends', category: 'Pets', memberLimit: 40, image: 'club_dogs.jpg',
    description: 'For dog lovers in the community. Arrange group walks and playdates, share trusted sitters and vets, and swap training tips.' },
  { id: 'gastro', label: 'Gastro', name: 'Food Lovers', category: 'Food & Drink', memberLimit: 25, image: 'club_gastro.jpg',
    description: 'Explore local restaurants together, host supper clubs and share the best places to eat nearby. Good food, good company.' },
] as const;
