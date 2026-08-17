// 100+ creative prompts. Rotates by hour; no repeats within a session.
class PromptService {
  PromptService._();
  static final PromptService instance = PromptService._();

  static const _all = [
    // Visual prompts (90%)
    'Post your view right now 👀',
    'Show me what you\'re eating 🍕',
    'Your current vibe ✨',
    'What\'s making you smile today? 😊',
    'Show your workspace 💻',
    'Your feet rn 👟',
    'Sky view from where you are ☁️',
    'Something blue 💙',
    'Your coffee or tea rn 🍵',
    'Post a mirror selfie 🪞',
    'Show your pet or plants 🐱',
    'Window view 🪟',
    'Your desk — mess or organized? 📚',
    'What\'s in your bag? 👜',
    'Show the sunset 🌅',
    'Post a candid laugh 🤣',
    'Your current snack 🥨',
    'Your chill spot 🎧',
    'What are you listening to? 🎵',
    'Show something you made 🛠️',
    'Your favorite shoes 👞',
    'Morning or night routine 🧴',
    'Your campus right now 🏫',
    'Close-up of something beautiful 🌸',
    'What\'s in your fridge? 🧊',
    'One object matching your mood 🎭',
    'Your handwriting ✍️',
    'The sky right now ☁️',
    'Your shadow 🌑',
    'Morning face — no filter 🥱',
    'The last thing you bought 🛍️',
    'What\'s on your table right now? 🍽️',
    'Something that inspires you ✨',
    'Your favorite mug ☕',
    'Something yellow 💛',
    'Your journal or planner 📓',
    'What you doodled today 🎨',
    'Your favorite plant 🪴',
    'Something round ⭕',
    'The last thing you cooked 🍳',
    'Your sunglasses 🕶️',
    'What\'s outside your door? 🚪',
    'The sky at golden hour 🌇',
    'Your go-to comfort food 🍲',
    'Your reflection in water 💧',
    'An empty street or hallway 🚶',
    'Your hands doing something 🙌',
    'Something you collect 🗂️',
    'First thing you see in the morning 👁️',
    'Night lights around you 🌃',
    'An artistic angle of anything 🔲',
    'Your latest purchase 💳',
    'Something small but mighty 🔬',
    'Something that smells amazing 🌺',
    'Your weekend energy 🛋️',
    'A blurry or motion photo 🌀',
    'Something red 🔴',
    'Show the prettiest thing near you 💐',
    'Post your power pose 💪',
    'Post an aesthetic flat lay 📐',
    'Your messy bun or hairstyle 💇',
    'The vending machine near you 🤖',
    'Your campus canteen today 🍽️',
    'That one spot only locals know 📍',
    'Your current book or manga 📖',
    'Your go-to outfit today 👔',
    'Old photo from your gallery 📼',
    'Your vehicle 🚗',
    'Your favorite city spot 🏙️',
    'Your screen time right now 📊',
    'Something that grounds you 🌍',
    'The most used app on your phone 📲',
    'Something sparkly ✨',
    'Something textured 🧱',
    'Your lunch box or tiffin 🥡',
    'Your current wallpaper 📱',
    'Something old 🏺',
    'Something green 🌿',
    'A moment of just being you 🎬',
    'The last meme that made you laugh 😂',
    'Your hand + what you\'re holding 🤝',
    'Your go-to drink right now 🧃',
    'Something you\'re proud of 🏅',
    'Your favorite corner at home 🛏️',
    'Show what relaxes you 🛁',
    'Your setup right now 🖥️',
    'A color that makes you happy 🌈',
    'Post your view from the ground 📸',
    'The last notification you got 🔔',
    'Someone nearby without them knowing 🤫',
    'Your reflection in a dark screen 🖤',
    'Your favorite building on campus 🏛️',
    // Text prompts (10%)
    'Unfiltered thoughts rn',
    'Hot take on campus life 🔥',
    'Real rant, no filter',
    'Unpopular opinion 💬',
    'Confession ⛪',
    'What nobody talks about...',
    'Your honest review of today',
    'Rate your day 1–10',
    'One word for your mood',
    'Hot goss 👀',
  ];

  final _seen = <int>{};
  int _pos = -1;

  String get current {
    if (_pos == -1) _init();
    return _all[_pos];
  }

  String advance() {
    if (_pos == -1) _init();
    _seen.add(_pos);
    if (_seen.length >= _all.length) _seen.clear();
    _pos = _nextUnseen();
    return _all[_pos];
  }

  void _init() {
    _pos = DateTime.now().hour % _all.length;
    if (_seen.contains(_pos)) _pos = _nextUnseen();
  }

  int _nextUnseen() {
    var p = (_pos + 1) % _all.length;
    var tries = 0;
    while (_seen.contains(p) && tries < _all.length) {
      p = (p + 1) % _all.length;
      tries++;
    }
    return p;
  }
}
