import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../shared/score_tier.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _Community {
  const _Community({
    required this.id,
    required this.label,
    required this.memberCount,
    required this.activeNow,
  });
  final String id;
  final String label;
  final int memberCount;
  final int activeNow;
}

class _Comment {
  const _Comment({
    required this.realName,
    required this.handle,
    required this.text,
    required this.time,
    this.avatarColor = const Color(0xFF1A2030),
  });
  final String realName;
  final String handle;
  final String text;
  final String time;
  final Color avatarColor;
}

class _NewsPost {
  const _NewsPost({
    required this.id,
    required this.handle,
    required this.realName,
    required this.text,
    required this.time,
    required this.score,
    required this.pingCount,
    required this.watchCount,
    this.hasPhoto = false,
    this.photoColor = const Color(0xFF1A2030),
    this.reactions = const {'🔥': 0, '💀': 0, '⭕': 0, '👀': 0},
    this.comments = const [],
  });
  final int id;
  final String handle;
  final String realName;
  final String text;
  final String time;
  final int score;
  final int pingCount;
  final int watchCount;
  final bool hasPhoto;
  final Color photoColor;
  final Map<String, int> reactions;
  final List<_Comment> comments;
}

class _LeaderEntry {
  const _LeaderEntry({
    required this.rank,
    required this.handle,
    required this.score,
    required this.delta,
    this.isMe = false,
  });
  final int rank;
  final String handle;
  final int score;
  final int delta; // weekly change
  final bool isMe;
}

enum _RowLayout { full, halves, bigLeft, bigRight }

class _MasonryRow {
  const _MasonryRow({required this.layout, required this.posts});
  final _RowLayout layout;
  final List<_NewsPost> posts;
}

// ---------------------------------------------------------------------------
// Dummy data
// ---------------------------------------------------------------------------

const _communities = [
  _Community(id: 'cse', label: 'CSE', memberCount: 547, activeNow: 89),
  _Community(id: '3rd', label: '3rd Year', memberCount: 623, activeNow: 112),
  _Community(id: 'campus', label: 'Campus', memberCount: 2341, activeNow: 156),
  _Community(id: 'photo', label: 'Photo Club', memberCount: 89, activeNow: 18),
  _Community(id: 'all', label: 'All', memberCount: 3600, activeNow: 375),
];

const _newsPosts = {
  'cse': [
    _NewsPost(
      id: 1,
      handle: 'debug_zero',
      realName: 'Aarav Mehta',
      text: 'Prof just moved the DBMS submission to Friday instead of Thursday and I have never felt more alive',
      time: '30m',
      score: 312,
      pingCount: 41,
      watchCount: 89,
      reactions: {'🔥': 84, '💀': 12, '⭕': 31, '👀': 47},
      comments: [
        _Comment(realName: 'Priya Sinha', handle: 'null_ptr', text: 'He always does this at the last minute lol', time: '25m', avatarColor: Color(0xFF1A2840)),
        _Comment(realName: 'Dev Nair', handle: 'pointer_v', text: 'Thursday would have been a bloodbath honestly', time: '18m', avatarColor: Color(0xFF182030)),
      ],
    ),
    _NewsPost(
      id: 2,
      handle: 'null_ptr',
      realName: 'Priya Sinha',
      text: 'Can we talk about how the lab PCs take 10 minutes to boot? Some of us have 1-hour labs.',
      time: '3h',
      score: 189,
      pingCount: 22,
      watchCount: 56,
      hasPhoto: true,
      photoColor: Color(0xFF1A2840),
      reactions: {'🔥': 56, '💀': 34, '⭕': 8, '👀': 29},
      comments: [
        _Comment(realName: 'Aarav Mehta', handle: 'debug_zero', text: 'I just go straight to the back row machines, those boot faster for some reason', time: '2h 45m', avatarColor: Color(0xFF141A28)),
      ],
    ),
    _NewsPost(
      id: 3,
      handle: 'loop_forever',
      realName: 'Karthik Rajan',
      text: "Anyone have the OS assignment solutions? Not copying, just want to check if I'm on the right track 👀",
      time: '5h',
      score: 67,
      pingCount: 8,
      watchCount: 23,
      reactions: {'🔥': 14, '💀': 7, '⭕': 22, '👀': 63},
    ),
    _NewsPost(
      id: 4,
      handle: 'byte_ghost',
      realName: 'Aisha Patel',
      text: 'The wifi near lab 3 keeps dropping every 20 minutes. Making pair programming literally impossible.',
      time: '6h',
      score: 145,
      pingCount: 19,
      watchCount: 44,
      hasPhoto: true,
      photoColor: Color(0xFF202838),
      reactions: {'🔥': 38, '💀': 29, '⭕': 5, '👀': 17},
      comments: [
        _Comment(realName: 'Sneha Gupta', handle: 'hex_dreams', text: 'Hotspot is the only solution at this point', time: '5h', avatarColor: Color(0xFF201828)),
        _Comment(realName: 'Rohan Verma', handle: 'stack_verse', text: 'Filed a complaint 3 weeks ago still nothing', time: '4h 30m', avatarColor: Color(0xFF142020)),
      ],
    ),
    _NewsPost(
      id: 5,
      handle: 'stack_verse',
      realName: 'Rohan Verma',
      text: 'Just deployed my first backend on Railway. Took 6 hours and I cried twice but it works.',
      time: '8h',
      score: 287,
      pingCount: 35,
      watchCount: 78,
      reactions: {'🔥': 112, '💀': 4, '⭕': 19, '👀': 38},
      comments: [
        _Comment(realName: 'Aarav Mehta', handle: 'debug_zero', text: 'The env variable issue gets everyone the first time', time: '7h', avatarColor: Color(0xFF141A28)),
        _Comment(realName: 'Meera Joshi', handle: 'cloud_nine', text: 'Railway for side projects is genuinely so good', time: '6h', avatarColor: Color(0xFF101828)),
      ],
    ),
    _NewsPost(
      id: 6,
      handle: 'hex_dreams',
      realName: 'Sneha Gupta',
      text: 'Which elective is everyone taking next sem? ML or Networks?',
      time: '10h',
      score: 203,
      pingCount: 28,
      watchCount: 61,
      reactions: {'🔥': 29, '💀': 6, '⭕': 44, '👀': 88},
    ),
    _NewsPost(
      id: 7,
      handle: 'pointer_v',
      realName: 'Dev Nair',
      text: 'Reminder: the project demo is Monday not Tuesday. Three of us almost missed it.',
      time: '12h',
      score: 98,
      pingCount: 14,
      watchCount: 37,
      reactions: {'🔥': 7, '💀': 3, '⭕': 2, '👀': 92},
    ),
    _NewsPost(
      id: 8,
      handle: 'cloud_nine',
      realName: 'Meera Joshi',
      text: 'Found out I was the only one to pass the snap test. The curve is going to save everyone else I guess.',
      time: '14h',
      score: 421,
      pingCount: 52,
      watchCount: 103,
      hasPhoto: true,
      photoColor: Color(0xFF182030),
      reactions: {'🔥': 143, '💀': 67, '⭕': 12, '👀': 55},
      comments: [
        _Comment(realName: 'Karthik Rajan', handle: 'loop_forever', text: 'respectfully: you did not have to post this 😭', time: '13h', avatarColor: Color(0xFF1A2018)),
        _Comment(realName: 'Priya Sinha', handle: 'null_ptr', text: 'We needed this curve please never tell sir', time: '12h', avatarColor: Color(0xFF1A2840)),
      ],
    ),
  ],
  '3rd': [
    _NewsPost(
      id: 10,
      handle: 'third_life',
      realName: 'Arjun Kumar',
      text: 'Internship season is killing me. Applied to 20 places, heard back from 0.',
      time: '45m',
      score: 445,
      pingCount: 63,
      watchCount: 134,
      reactions: {'🔥': 34, '💀': 189, '⭕': 22, '👀': 76},
      comments: [
        _Comment(realName: 'Vikram Iyer', handle: 'resume_run', text: 'Same. The rejection silence is worse than actual rejections', time: '40m', avatarColor: Color(0xFF1A2818)),
        _Comment(realName: 'Nisha Sharma', handle: 'barely_awake', text: 'Keep going. Referrals help way more than cold apps', time: '30m', avatarColor: Color(0xFF28201A)),
        _Comment(realName: 'Divya Krishnan', handle: 'night_cram', text: 'LinkedIn is a simulation. Try your seniors directly', time: '20m', avatarColor: Color(0xFF201218)),
      ],
    ),
    _NewsPost(
      id: 11,
      handle: 'barely_awake',
      realName: 'Nisha Sharma',
      text: 'Does anyone actually understand what happened in Advanced Algorithms today or was it just me',
      time: '2h',
      score: 201,
      pingCount: 29,
      watchCount: 67,
      hasPhoto: true,
      photoColor: Color(0xFF28201A),
      reactions: {'🔥': 11, '💀': 78, '⭕': 9, '👀': 134},
    ),
    _NewsPost(
      id: 12,
      handle: 'half_credit',
      realName: 'Siddharth Bose',
      text: 'Reminder that 3rd year is not as scary as 2nd year seniors made it sound. It is exactly as scary.',
      time: '6h',
      score: 378,
      pingCount: 47,
      watchCount: 98,
      reactions: {'🔥': 67, '💀': 145, '⭕': 8, '👀': 43},
      comments: [
        _Comment(realName: 'Ananya Rao', handle: 'lost_sem', text: 'They lied to us so naturally', time: '5h', avatarColor: Color(0xFF181828)),
      ],
    ),
    _NewsPost(
      id: 13,
      handle: 'lost_sem',
      realName: 'Ananya Rao',
      text: 'GPA anxiety is at an all-time high and mid-sems are still 3 weeks away.',
      time: '8h',
      score: 289,
      pingCount: 34,
      watchCount: 72,
      reactions: {'🔥': 23, '💀': 201, '⭕': 14, '👀': 56},
    ),
    _NewsPost(
      id: 14,
      handle: 'resume_run',
      realName: 'Vikram Iyer',
      text: 'Just got my first offer letter. It is a startup, pay is mid, but I cried anyway.',
      time: '11h',
      score: 512,
      pingCount: 71,
      watchCount: 156,
      hasPhoto: true,
      photoColor: Color(0xFF1A2818),
      reactions: {'🔥': 289, '💀': 5, '⭕': 34, '👀': 112},
      comments: [
        _Comment(realName: 'Arjun Kumar', handle: 'third_life', text: 'Congrats!! Which company if you can share?', time: '10h', avatarColor: Color(0xFF1A1828)),
        _Comment(realName: 'Siddharth Bose', handle: 'half_credit', text: 'You deserve this fr. You were grinding for months', time: '9h', avatarColor: Color(0xFF181820)),
        _Comment(realName: 'Divya Krishnan', handle: 'night_cram', text: 'First offer is always emotional, congrats!!', time: '8h', avatarColor: Color(0xFF201218)),
      ],
    ),
    _NewsPost(
      id: 15,
      handle: 'night_cram',
      realName: 'Divya Krishnan',
      text: 'Why does every prof schedule submissions on the same day',
      time: '13h',
      score: 334,
      pingCount: 43,
      watchCount: 89,
      reactions: {'🔥': 56, '💀': 167, '⭕': 11, '👀': 44},
    ),
  ],
  'campus': [
    _NewsPost(
      id: 20,
      handle: 'ghost_301',
      realName: 'Rahul Desai',
      text: 'The wifi near the library has been dead for 3 days. Are they fixing it or should I switch colleges 😭',
      time: '12m',
      score: 87,
      pingCount: 11,
      watchCount: 29,
      reactions: {'🔥': 8, '💀': 56, '⭕': 4, '👀': 33},
      comments: [
        _Comment(realName: 'Kavya Menon', handle: 'silent_river', text: 'It was dead last week too, they just said router issue', time: '8m', avatarColor: Color(0xFF12181A)),
      ],
    ),
    _NewsPost(
      id: 21,
      handle: 'silent_river',
      realName: 'Kavya Menon',
      text: 'Anyone else notice how the canteen prices went up again without any notice?',
      time: '1h',
      score: 234,
      pingCount: 31,
      watchCount: 78,
      hasPhoto: true,
      photoColor: Color(0xFF201A12),
      reactions: {'🔥': 45, '💀': 89, '⭕': 17, '👀': 34},
      comments: [
        _Comment(realName: 'Rishi Kapoor', handle: 'rooftop_kid', text: 'Vada pav went from 15 to 25 I am not okay', time: '55m', avatarColor: Color(0xFF201412)),
        _Comment(realName: 'Zara Ahmed', handle: 'exam_ghost', text: 'They did this last semester too and nobody said anything', time: '40m', avatarColor: Color(0xFF1A1820)),
      ],
    ),
    _NewsPost(
      id: 22,
      handle: 'foggy_lens',
      realName: 'Aditya Singh',
      text: 'Found a quiet corner in block C that nobody uses. My new study spot until someone finds it.',
      time: '2h',
      score: 45,
      pingCount: 6,
      watchCount: 14,
      reactions: {'🔥': 12, '💀': 3, '⭕': 28, '👀': 19},
    ),
    _NewsPost(
      id: 23,
      handle: 'campus_owl',
      realName: 'Pooja Nair',
      text: 'The new benches near the main gate actually slap. Someone finally fixed campus aesthetics.',
      time: '4h',
      score: 167,
      pingCount: 21,
      watchCount: 48,
      hasPhoto: true,
      photoColor: Color(0xFF12201A),
      reactions: {'🔥': 78, '💀': 4, '⭕': 23, '👀': 41},
    ),
    _NewsPost(
      id: 24,
      handle: 'rooftop_kid',
      realName: 'Rishi Kapoor',
      text: 'Sunset from the terrace today was genuinely unreal. No filter.',
      time: '6h',
      score: 389,
      pingCount: 52,
      watchCount: 112,
      hasPhoto: true,
      photoColor: Color(0xFF2A1810),
      reactions: {'🔥': 234, '💀': 8, '⭕': 19, '👀': 145},
      comments: [
        _Comment(realName: 'Pooja Nair', handle: 'campus_owl', text: 'The colours yesterday were insane, which floor?', time: '5h', avatarColor: Color(0xFF0A1A10)),
        _Comment(realName: 'Tanvi Pillai', handle: 'rain_walker', text: 'I was there too!! Should have said hi', time: '4h', avatarColor: Color(0xFF1A1018)),
      ],
    ),
    _NewsPost(
      id: 25,
      handle: 'exam_ghost',
      realName: 'Zara Ahmed',
      text: 'Hot take: the new seating arrangement in the library makes everything worse.',
      time: '9h',
      score: 201,
      pingCount: 27,
      watchCount: 63,
      reactions: {'🔥': 34, '💀': 23, '⭕': 56, '👀': 28},
    ),
    _NewsPost(
      id: 26,
      handle: 'rain_walker',
      realName: 'Tanvi Pillai',
      text: 'Someone left their umbrella on the 2nd floor stairs. Still there after 2 days. Hero behavior.',
      time: '11h',
      score: 134,
      pingCount: 18,
      watchCount: 41,
      reactions: {'🔥': 45, '💀': 6, '⭕': 12, '👀': 23},
    ),
  ],
  'photo': [
    _NewsPost(
      id: 30,
      handle: 'f_stop_8',
      realName: 'Ishaan Bose',
      text: 'Golden hour from the terrace yesterday was insane. Posted it on the club drive.',
      time: '20m',
      score: 56,
      pingCount: 7,
      watchCount: 18,
      hasPhoto: true,
      photoColor: Color(0xFF2A1808),
      reactions: {'🔥': 34, '💀': 2, '⭕': 8, '👀': 19},
      comments: [
        _Comment(realName: 'Kabir Patel', handle: 'shutter_soul', text: 'That f/1.8 golden hour glow is unmatched', time: '15m', avatarColor: Color(0xFF18101A)),
      ],
    ),
    _NewsPost(
      id: 31,
      handle: 'grain_film',
      realName: 'Lakshmi Srinivasan',
      text: 'Can someone explain why my photos look amazing in Lightroom and terrible after export?',
      time: '4h',
      score: 34,
      pingCount: 4,
      watchCount: 11,
      reactions: {'🔥': 9, '💀': 14, '⭕': 3, '👀': 22},
      comments: [
        _Comment(realName: 'Anjali Kumar', handle: 'dark_room_rx', text: 'Export colour profile — set to sRGB not Display P3', time: '3h', avatarColor: Color(0xFF1A1018)),
        _Comment(realName: 'Ishaan Bose', handle: 'f_stop_8', text: 'Also check your export sharpening settings', time: '2h', avatarColor: Color(0xFF1A1408)),
      ],
    ),
    _NewsPost(
      id: 32,
      handle: 'shutter_soul',
      realName: 'Kabir Patel',
      text: 'Borrowed a 50mm prime for the weekend. Everything looks like a movie now.',
      time: '7h',
      score: 78,
      pingCount: 10,
      watchCount: 22,
      hasPhoto: true,
      photoColor: Color(0xFF18101A),
      reactions: {'🔥': 56, '💀': 3, '⭕': 14, '👀': 31},
    ),
    _NewsPost(
      id: 33,
      handle: 'dark_room_rx',
      realName: 'Anjali Kumar',
      text: 'First time developing film. Ruined the first roll. Second roll came out perfect.',
      time: '10h',
      score: 112,
      pingCount: 14,
      watchCount: 31,
      reactions: {'🔥': 67, '💀': 4, '⭕': 11, '👀': 28},
      comments: [
        _Comment(realName: 'Lakshmi Srinivasan', handle: 'grain_film', text: 'Which film stock? Kodak Gold?', time: '9h', avatarColor: Color(0xFF181218)),
        _Comment(realName: 'Kabir Patel', handle: 'shutter_soul', text: 'The second roll feeling is indescribable honestly', time: '8h', avatarColor: Color(0xFF18101A)),
      ],
    ),
  ],
  'all': [
    _NewsPost(
      id: 40,
      handle: 'campus_owl',
      realName: 'Pooja Nair',
      text: 'The new benches near the main gate actually slap.',
      time: '12m',
      score: 167,
      pingCount: 21,
      watchCount: 48,
      reactions: {'🔥': 78, '💀': 4, '⭕': 23, '👀': 41},
    ),
    _NewsPost(
      id: 41,
      handle: 'debug_zero',
      realName: 'Aarav Mehta',
      text: 'Prof just moved the DBMS submission to Friday and I have never felt more alive',
      time: '35m',
      score: 312,
      pingCount: 41,
      watchCount: 89,
      reactions: {'🔥': 84, '💀': 12, '⭕': 31, '👀': 47},
    ),
    _NewsPost(
      id: 42,
      handle: 'third_life',
      realName: 'Arjun Kumar',
      text: 'Internship season is killing me. Applied to 20, heard back from 0.',
      time: '1h',
      score: 445,
      pingCount: 63,
      watchCount: 134,
      hasPhoto: true,
      photoColor: Color(0xFF1A1828),
      reactions: {'🔥': 34, '💀': 189, '⭕': 22, '👀': 76},
    ),
    _NewsPost(
      id: 43,
      handle: 'f_stop_8',
      realName: 'Ishaan Bose',
      text: 'Golden hour from the terrace yesterday was insane.',
      time: '2h',
      score: 56,
      pingCount: 7,
      watchCount: 18,
      hasPhoto: true,
      photoColor: Color(0xFF2A1808),
      reactions: {'🔥': 34, '💀': 2, '⭕': 8, '👀': 19},
    ),
    _NewsPost(
      id: 44,
      handle: 'half_credit',
      realName: 'Siddharth Bose',
      text: '3rd year is exactly as scary as the seniors made it sound.',
      time: '3h',
      score: 378,
      pingCount: 47,
      watchCount: 98,
      reactions: {'🔥': 67, '💀': 145, '⭕': 8, '👀': 43},
    ),
    _NewsPost(
      id: 45,
      handle: 'insomnia_42',
      realName: 'Arnav Sharma',
      text: "It's 2am and I'm writing a lab record due at 8am. This is fine.",
      time: '4h',
      score: 267,
      pingCount: 34,
      watchCount: 74,
      reactions: {'🔥': 78, '💀': 134, '⭕': 9, '👀': 56},
    ),
    _NewsPost(
      id: 46,
      handle: 'silent_river',
      realName: 'Kavya Menon',
      text: 'Anyone else notice how the canteen prices went up again without notice?',
      time: '6h',
      score: 234,
      pingCount: 31,
      watchCount: 78,
      hasPhoto: true,
      photoColor: Color(0xFF201A12),
      reactions: {'🔥': 45, '💀': 89, '⭕': 17, '👀': 34},
    ),
    _NewsPost(
      id: 47,
      handle: 'rooftop_kid',
      realName: 'Rishi Kapoor',
      text: 'Sunset from the terrace today was genuinely unreal. No filter.',
      time: '8h',
      score: 389,
      pingCount: 52,
      watchCount: 112,
      hasPhoto: true,
      photoColor: Color(0xFF2A1810),
      reactions: {'🔥': 234, '💀': 8, '⭕': 19, '👀': 145},
    ),
  ],
};

const _leaderboards = {
  'cse': [
    _LeaderEntry(rank: 1, handle: 'night_owl', score: 342, delta: 28),
    _LeaderEntry(rank: 2, handle: 'forest_lens', score: 298, delta: 15),
    _LeaderEntry(rank: 3, handle: 'silent_storm', score: 267, delta: -4),
    _LeaderEntry(rank: 4, handle: 'debug_zero', score: 231, delta: 41),
    _LeaderEntry(rank: 5, handle: 'byte_ghost', score: 198, delta: 19),
    _LeaderEntry(rank: 6, handle: 'null_ptr', score: 176, delta: -8),
    _LeaderEntry(rank: 7, handle: 'you', score: 154, delta: 22, isMe: true),
    _LeaderEntry(rank: 8, handle: 'loop_forever', score: 134, delta: 6),
    _LeaderEntry(rank: 9, handle: 'stack_verse', score: 112, delta: -3),
    _LeaderEntry(rank: 10, handle: 'hex_dreams', score: 89, delta: 11),
  ],
  '3rd': [
    _LeaderEntry(rank: 1, handle: 'resume_run', score: 512, delta: 67),
    _LeaderEntry(rank: 2, handle: 'third_life', score: 445, delta: 31),
    _LeaderEntry(rank: 3, handle: 'half_credit', score: 378, delta: 12),
    _LeaderEntry(rank: 4, handle: 'lost_sem', score: 289, delta: -6),
    _LeaderEntry(rank: 5, handle: 'barely_awake', score: 201, delta: 9),
    _LeaderEntry(rank: 6, handle: 'night_cram', score: 167, delta: 18),
    _LeaderEntry(rank: 7, handle: 'you', score: 143, delta: 27, isMe: true),
    _LeaderEntry(rank: 8, handle: 'exam_ghost', score: 121, delta: -2),
    _LeaderEntry(rank: 9, handle: 'rain_walker', score: 98, delta: 7),
    _LeaderEntry(rank: 10, handle: 'grad_run', score: 76, delta: 4),
  ],
  'campus': [
    _LeaderEntry(rank: 1, handle: 'rooftop_kid', score: 789, delta: 54),
    _LeaderEntry(rank: 2, handle: 'campus_owl', score: 634, delta: 38),
    _LeaderEntry(rank: 3, handle: 'silent_river', score: 567, delta: 21),
    _LeaderEntry(rank: 4, handle: 'ghost_301', score: 489, delta: -12),
    _LeaderEntry(rank: 5, handle: 'foggy_lens', score: 398, delta: 29),
    _LeaderEntry(rank: 6, handle: 'exam_ghost', score: 312, delta: 8),
    _LeaderEntry(rank: 7, handle: 'you', score: 287, delta: 33, isMe: true),
    _LeaderEntry(rank: 8, handle: 'rain_walker', score: 234, delta: 5),
    _LeaderEntry(rank: 9, handle: 'bench_kid', score: 178, delta: 14),
    _LeaderEntry(rank: 10, handle: 'tea_stall', score: 143, delta: -7),
  ],
  'photo': [
    _LeaderEntry(rank: 1, handle: 'shutter_soul', score: 234, delta: 19),
    _LeaderEntry(rank: 2, handle: 'f_stop_8', score: 189, delta: 12),
    _LeaderEntry(rank: 3, handle: 'dark_room_rx', score: 156, delta: 8),
    _LeaderEntry(rank: 4, handle: 'grain_film', score: 98, delta: -3),
    _LeaderEntry(rank: 5, handle: 'you', score: 67, delta: 14, isMe: true),
    _LeaderEntry(rank: 6, handle: 'aperture_x', score: 45, delta: 6),
  ],
  'all': [
    _LeaderEntry(rank: 1, handle: 'rooftop_kid', score: 1243, delta: 89),
    _LeaderEntry(rank: 2, handle: 'resume_run', score: 987, delta: 112),
    _LeaderEntry(rank: 3, handle: 'night_owl', score: 876, delta: 43),
    _LeaderEntry(rank: 4, handle: 'campus_owl', score: 765, delta: 38),
    _LeaderEntry(rank: 5, handle: 'debug_zero', score: 654, delta: 67),
    _LeaderEntry(rank: 6, handle: 'third_life', score: 567, delta: 31),
    _LeaderEntry(rank: 7, handle: 'you', score: 498, delta: 74, isMe: true),
    _LeaderEntry(rank: 8, handle: 'silent_river', score: 423, delta: 21),
    _LeaderEntry(rank: 9, handle: 'forest_lens', score: 378, delta: 15),
    _LeaderEntry(rank: 10, handle: 'half_credit', score: 312, delta: 9),
  ],
};

// Hotspot data for map
class _MapHotspot {
  const _MapHotspot({
    required this.name,
    required this.xFraction,
    required this.yFraction,
    required this.intensity, // 0.0 – 1.0
    required this.postCount,
  });
  final String name;
  final double xFraction;
  final double yFraction;
  final double intensity;
  final int postCount;
}

const _campusHotspots = [
  _MapHotspot(name: 'Library', xFraction: 0.35, yFraction: 0.28, intensity: 0.9, postCount: 47),
  _MapHotspot(name: 'Canteen', xFraction: 0.62, yFraction: 0.55, intensity: 1.0, postCount: 63),
  _MapHotspot(name: 'CSE Block', xFraction: 0.25, yFraction: 0.60, intensity: 0.7, postCount: 31),
  _MapHotspot(name: 'Main Gate', xFraction: 0.72, yFraction: 0.18, intensity: 0.4, postCount: 18),
  _MapHotspot(name: 'Physics Lab', xFraction: 0.55, yFraction: 0.75, intensity: 0.5, postCount: 22),
  _MapHotspot(name: 'Terrace', xFraction: 0.80, yFraction: 0.38, intensity: 0.6, postCount: 27),
];

// Build masonry rows from a post list
List<_MasonryRow> _buildMasonryRows(List<_NewsPost> posts) {
  final rows = <_MasonryRow>[];
  var i = 0;
  var patternIndex = 0;
  const patterns = [
    _RowLayout.full,
    _RowLayout.halves,
    _RowLayout.bigLeft,
    _RowLayout.halves,
    _RowLayout.full,
    _RowLayout.bigRight,
    _RowLayout.halves,
    _RowLayout.bigLeft,
  ];

  while (i < posts.length) {
    final layout = patterns[patternIndex % patterns.length];
    final needed = layout == _RowLayout.full ? 1 : 2;
    final available = posts.length - i;

    if (available == 1) {
      rows.add(_MasonryRow(layout: _RowLayout.full, posts: [posts[i]]));
      i++;
    } else {
      rows.add(_MasonryRow(
        layout: available >= needed ? layout : _RowLayout.halves,
        posts: posts.sublist(i, i + math.min(needed, available)),
      ));
      i += math.min(needed, available);
    }
    patternIndex++;
  }
  return rows;
}

// ---------------------------------------------------------------------------
// CommunityScreen
// ---------------------------------------------------------------------------

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  int _communityIndex = 0;
  int _sectionIndex = 0;
  late final PageController _pageCtrl;
  late final TabController _tabCtrl;
  final _sectionScrollCtrls = List.generate(3, (_) => ScrollController());

  _Community get _activeCommunity => _communities[_communityIndex];
  String get _activeId => _activeCommunity.id;

  List<_NewsPost> get _activePosts =>
      _newsPosts[_activeId] ?? _newsPosts['all']!;
  List<_LeaderEntry> get _activeLeaderboard =>
      _leaderboards[_activeId] ?? _leaderboards['all']!;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _tabCtrl.dispose();
    for (final c in _sectionScrollCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _switchCommunity(int index) {
    HapticFeedback.selectionClick();
    setState(() => _communityIndex = index);
  }

  void _switchSection(int index) {
    HapticFeedback.selectionClick();
    setState(() => _sectionIndex = index);
    _pageCtrl.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Status bar spacer + title ────────────────────────────────────
          SizedBox(height: topPad + 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'community',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppColors.textPrimary,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Community tabs (horizontal scroll) ──────────────────────────
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _communities.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final active = i == _communityIndex;
                return GestureDetector(
                  onTap: () => _switchCommunity(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.coral.withValues(alpha: 0.15)
                          : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active
                            ? AppColors.coral.withValues(alpha: 0.55)
                            : AppColors.border,
                        width: active ? 1.2 : 1.0,
                      ),
                    ),
                    child: Text(
                      _communities[i].label,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? AppColors.coral : AppColors.textMuted,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // ── Section pills ────────────────────────────────────────────────
          _SectionPills(
            selected: _sectionIndex,
            onSelect: _switchSection,
          ),

          const SizedBox(height: 12),

          // ── PageView — swipeable sections ────────────────────────────────
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const ClampingScrollPhysics(),
              onPageChanged: (i) => setState(() => _sectionIndex = i),
              children: [
                _NewsSection(
                  posts: _activePosts,
                  communityLabel: _activeCommunity.label,
                  scrollCtrl: _sectionScrollCtrls[0],
                  bottomPad: bottomPad,
                ),
                _MapSection(
                  communityLabel: _activeCommunity.label,
                  scrollCtrl: _sectionScrollCtrls[1],
                  bottomPad: bottomPad,
                ),
                _LeaderboardSection(
                  entries: _activeLeaderboard,
                  communityLabel: _activeCommunity.label,
                  scrollCtrl: _sectionScrollCtrls[2],
                  bottomPad: bottomPad,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section pills [News] [Map] [Leaderboard]
// ---------------------------------------------------------------------------

class _SectionPills extends StatelessWidget {
  const _SectionPills({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  static const _labels = ['News', 'Map', 'Leaderboard'];
  static const _icons = [
    Icons.article_outlined,
    Icons.map_outlined,
    Icons.emoji_events_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: List.generate(_labels.length, (i) {
            final active = i == selected;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color:
                        active ? AppColors.coral : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _icons[i],
                        size: 13,
                        color: active
                            ? Colors.white
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _labels[i],
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active
                              ? Colors.white
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NEWS SECTION — newspaper-style masonry grid
// ---------------------------------------------------------------------------

class _NewsSection extends StatelessWidget {
  const _NewsSection({
    required this.posts,
    required this.communityLabel,
    required this.scrollCtrl,
    required this.bottomPad,
  });

  final List<_NewsPost> posts;
  final String communityLabel;
  final ScrollController scrollCtrl;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    final rows = _buildMasonryRows(posts);

    return ListView.separated(
      controller: scrollCtrl,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPad + 96),
      itemCount: rows.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _MasonryRowWidget(row: rows[i]),
    );
  }
}

class _MasonryRowWidget extends StatelessWidget {
  const _MasonryRowWidget({required this.row});

  final _MasonryRow row;

  // Heights for each layout role
  static const _fullHeight = 192.0;
  static const _halfHeight = 160.0;
  static const _bigHeight = 178.0;
  static const _smallHeight = 130.0;

  @override
  Widget build(BuildContext context) {
    switch (row.layout) {
      case _RowLayout.full:
        return _PostTile(post: row.posts[0], height: _fullHeight);

      case _RowLayout.halves:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PostTile(post: row.posts[0], height: _halfHeight),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: row.posts.length > 1
                  ? _PostTile(post: row.posts[1], height: _halfHeight)
                  : const SizedBox(),
            ),
          ],
        );

      case _RowLayout.bigLeft:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _PostTile(post: row.posts[0], height: _bigHeight),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: row.posts.length > 1
                  ? _PostTile(post: row.posts[1], height: _smallHeight)
                  : const SizedBox(),
            ),
          ],
        );

      case _RowLayout.bigRight:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _PostTile(post: row.posts[0], height: _smallHeight),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: row.posts.length > 1
                  ? _PostTile(post: row.posts[1], height: _bigHeight)
                  : const SizedBox(),
            ),
          ],
        );
    }
  }
}

class _PostTile extends StatefulWidget {
  const _PostTile({required this.post, required this.height});

  final _NewsPost post;
  final double height;

  @override
  State<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<_PostTile> {
  bool _pressed = false;

  void _openDetail(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PostDetailScreen(post: widget.post),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isShort = widget.height < 150;

    // Top-2 reactions by count for the compact strip
    final topReactions = post.reactions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visibleReactions = topReactions.take(isShort ? 2 : 3).toList();

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        _openDetail(context);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo background
              if (post.hasPhoto)
                Positioned(
                  top: 0, left: 0, right: 0,
                  height: isShort ? widget.height * 0.5 : widget.height * 0.45,
                  child: Container(
                    color: post.photoColor,
                    child: Center(
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: isShort ? 18 : 22,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ),

              // Content
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.hasPhoto)
                      SizedBox(
                        height: isShort
                            ? widget.height * 0.5
                            : widget.height * 0.45,
                      ),

                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          10, post.hasPhoto ? 7 : 10, 10, 7,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Real name + score
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        post.realName,
                                        style: GoogleFonts.inter(
                                          fontSize: isShort ? 10 : 11,
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (!isShort)
                                        Text(
                                          '@${post.handle}',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 8,
                                            color: AppColors.coral,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.coral.withValues(alpha: 0.45)),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '+${post.score}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 8,
                                      color: AppColors.coral,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),

                            // Post text
                            Expanded(
                              child: Text(
                                post.text,
                                style: GoogleFonts.inter(
                                  fontSize: isShort ? 11 : 12,
                                  color: AppColors.textPrimary,
                                  height: 1.4,
                                ),
                                overflow: TextOverflow.fade,
                              ),
                            ),

                            // Reactions strip + time
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                ...visibleReactions.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(e.key, style: const TextStyle(fontSize: 11)),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${e.value}',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 8,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  post.time,
                                  style: GoogleFonts.jetBrainsMono(fontSize: 8, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// POST DETAIL SCREEN — full-screen on tap
// ---------------------------------------------------------------------------

class _PostDetailScreen extends StatefulWidget {
  const _PostDetailScreen({required this.post});
  final _NewsPost post;

  @override
  State<_PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<_PostDetailScreen> {
  late final Map<String, int> _reactions;
  String? _myReaction;

  @override
  void initState() {
    super.initState();
    _reactions = Map<String, int>.from(widget.post.reactions);
  }

  void _react(String emoji) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_myReaction == emoji) {
        _reactions[emoji] = math.max(0, (_reactions[emoji] ?? 1) - 1);
        _myReaction = null;
      } else {
        if (_myReaction != null) {
          _reactions[_myReaction!] = math.max(0, (_reactions[_myReaction!] ?? 1) - 1);
        }
        _reactions[emoji] = (_reactions[emoji] ?? 0) + 1;
        _myReaction = emoji;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Scrollable content ─────────────────────────────────────────
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(0, topPad + 64, 0, bottomPad + 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photo
                if (post.hasPhoto)
                  Container(
                    width: double.infinity,
                    height: 260,
                    color: post.photoColor,
                    child: Center(
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 52,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author row
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.coral.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.coral.withValues(alpha: 0.40),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                post.realName[0],
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 17,
                                  color: AppColors.coral,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  post.realName,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '@${post.handle}  ·  ${post.time} ago',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Full post text
                      Text(
                        post.text,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          color: AppColors.textPrimary,
                          height: 1.55,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Reactions (live, tappable)
                      _ReactionsRow(
                        reactions: _reactions,
                        myReaction: _myReaction,
                        onReact: _react,
                      ),
                      const SizedBox(height: 10),

                      // Stats row
                      Row(
                        children: [
                          Icon(Icons.remove_red_eye_outlined, size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '${post.watchCount} watching',
                            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textMuted),
                          ),
                          const SizedBox(width: 14),
                          Icon(Icons.notifications_outlined, size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '${post.pingCount} pings',
                            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textMuted),
                          ),
                          const Spacer(),
                          Text(
                            '+${post.score} pts',
                            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.coral),
                          ),
                        ],
                      ),

                      // Comments
                      if (post.comments.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Text(
                              '${post.comments.length} comment${post.comments.length == 1 ? '' : 's'}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final c in post.comments) ...[
                          _CommentRow(comment: c),
                          const SizedBox(height: 10),
                        ],
                      ] else ...[
                        const SizedBox(height: 28),
                        Text(
                          'No comments yet — be first',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Fixed top bar ──────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.close_rounded, color: AppColors.textPrimary, size: 18),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'community',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 36),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// REACTIONS ROW — live tappable (used in detail screen)
// ---------------------------------------------------------------------------

class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({
    required this.reactions,
    required this.myReaction,
    required this.onReact,
  });

  final Map<String, int> reactions;
  final String? myReaction;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: reactions.entries.map((e) {
        final isSelected = e.key == myReaction;
        return GestureDetector(
          onTap: () => onReact(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.coral.withValues(alpha: 0.14)
                  : AppColors.cardSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected
                    ? AppColors.coral.withValues(alpha: 0.60)
                    : AppColors.border,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.key, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 7),
                Text(
                  '${e.value}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: isSelected ? AppColors.coral : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// COMMENT ROW — used in detail screen
// ---------------------------------------------------------------------------

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final _Comment comment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: comment.avatarColor,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Center(
            child: Text(
              comment.realName[0],
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.realName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '@${comment.handle}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppColors.coral),
                    ),
                    const Spacer(),
                    Text(
                      comment.time,
                      style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  comment.text,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// MAP SECTION — stylized campus map with activity heatmap
// ---------------------------------------------------------------------------

class _MapSection extends StatefulWidget {
  const _MapSection({
    required this.communityLabel,
    required this.scrollCtrl,
    required this.bottomPad,
  });

  final String communityLabel;
  final ScrollController scrollCtrl;
  final double bottomPad;

  @override
  State<_MapSection> createState() => _MapSectionState();
}

class _MapSectionState extends State<_MapSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mapH = size.width * 1.08; // roughly square-ish
    final bottomPad = widget.bottomPad;

    return ListView(
      controller: widget.scrollCtrl,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad + 96),
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Text(
                '${widget.communityLabel} • activity map',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.coral.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'live',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.coral,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Map canvas
        SizedBox(
          height: mapH,
          child: GestureDetector(
            onTapUp: (d) {
              final local = d.localPosition;
              _MapHotspot? hit;
              for (final h in _campusHotspots) {
                final hx = h.xFraction * size.width;
                final hy = h.yFraction * mapH;
                if ((local.dx - hx).abs() < 38 &&
                    (local.dy - hy).abs() < 38) {
                  hit = h;
                  break;
                }
              }
              if (hit != null) _showHotspotSheet(hit);
            },
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) => CustomPaint(
                size: Size(size.width, mapH),
                painter: _CampusMapPainter(
                  pulse: _pulseCtrl.value,
                  hotspots: _campusHotspots,
                ),
              ),
            ),
          ),
        ),

        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Activity hotspots — tap to see posts',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: _campusHotspots.map((h) {
                  return GestureDetector(
                    onTap: () => _showHotspotSheet(h),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.coral
                                  .withValues(alpha: h.intensity),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${h.name} (${h.postCount})',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showHotspotSheet(_MapHotspot hotspot) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _HotspotSheet(hotspot: hotspot),
    );
  }
}

class _CampusMapPainter extends CustomPainter {
  const _CampusMapPainter({
    required this.pulse,
    required this.hotspots,
  });

  final double pulse;
  final List<_MapHotspot> hotspots;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF08080E),
    );

    // Campus boundary
    final campusPaint = Paint()
      ..color = const Color(0xFF141420)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, h * 0.06, w * 0.88, h * 0.88),
        const Radius.circular(20),
      ),
      campusPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, h * 0.06, w * 0.88, h * 0.88),
        const Radius.circular(20),
      ),
      Paint()
        ..color = const Color(0xFF2A2A35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Roads
    final roadPaint = Paint()
      ..color = const Color(0xFF1E1E2A)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    // Horizontal main road
    canvas.drawLine(
      Offset(w * 0.10, h * 0.48),
      Offset(w * 0.90, h * 0.48),
      roadPaint,
    );
    // Vertical main road
    canvas.drawLine(
      Offset(w * 0.50, h * 0.10),
      Offset(w * 0.50, h * 0.90),
      roadPaint,
    );
    // Diagonal path
    canvas.drawLine(
      Offset(w * 0.20, h * 0.20),
      Offset(w * 0.80, h * 0.80),
      roadPaint..strokeWidth = 6,
    );

    // Buildings
    _drawBuilding(canvas, w * 0.12, h * 0.12, w * 0.22, h * 0.16, 'Library');
    _drawBuilding(canvas, w * 0.52, h * 0.44, w * 0.20, h * 0.16, 'Canteen');
    _drawBuilding(canvas, w * 0.12, h * 0.50, w * 0.18, h * 0.18, 'CSE');
    _drawBuilding(canvas, w * 0.65, h * 0.10, w * 0.14, h * 0.12, 'Gate');
    _drawBuilding(canvas, w * 0.45, h * 0.65, w * 0.20, h * 0.14, 'Physics');
    _drawBuilding(canvas, w * 0.68, h * 0.30, w * 0.16, h * 0.10, 'Terrace');
    _drawBuilding(canvas, w * 0.30, h * 0.70, w * 0.18, h * 0.12, 'Sports');
    _drawBuilding(canvas, w * 0.72, h * 0.65, w * 0.14, h * 0.16, 'Arts');

    // Green space (garden)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.30),
          width: w * 0.14,
          height: h * 0.10,
        ),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF0A1A0A),
    );

    // Heat circles at hotspots
    for (final spot in hotspots) {
      final cx = spot.xFraction * w;
      final cy = spot.yFraction * h;
      final baseR = 28.0 + spot.intensity * 20;
      final pulseR = baseR + pulse * 12 * spot.intensity;

      // Outer pulsing ring
      canvas.drawCircle(
        Offset(cx, cy),
        pulseR,
        Paint()
          ..color =
              AppColors.coral.withValues(alpha: 0.08 * spot.intensity)
          ..style = PaintingStyle.fill,
      );

      // Middle ring
      canvas.drawCircle(
        Offset(cx, cy),
        baseR * 0.70,
        Paint()
          ..color =
              AppColors.coral.withValues(alpha: 0.18 * spot.intensity),
      );

      // Core dot
      canvas.drawCircle(
        Offset(cx, cy),
        8 + spot.intensity * 6,
        Paint()
          ..color =
              AppColors.coral.withValues(alpha: 0.75 + 0.25 * spot.intensity),
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: spot.name,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            color: Colors.white.withValues(alpha: 0.55),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(cx - tp.width / 2, cy + 12 + spot.intensity * 6 + 4),
      );
    }
  }

  void _drawBuilding(
    Canvas canvas,
    double x,
    double y,
    double bw,
    double bh,
    String label,
  ) {
    final rect = Rect.fromLTWH(x, y, bw, bh);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF1C1C28),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = const Color(0xFF2E2E3C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_CampusMapPainter old) => old.pulse != pulse;
}

class _HotspotSheet extends StatelessWidget {
  const _HotspotSheet({required this.hotspot});

  final _MapHotspot hotspot;

  static const _dummyPosts = [
    'The wifi here is finally working again.',
    'Great place to work on assignments after 6pm.',
    'Someone left their charger here — it\'s at the front desk.',
    'Lines are shorter before 12:30.',
    'Quiet corner on the left side near the window.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF14141C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.coral
                        .withValues(alpha: hotspot.intensity),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  hotspot.name,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${hotspot.postCount} posts',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: AppColors.border, height: 1),

          // Mini post list
          for (var i = 0; i < math.min(3, _dummyPosts.length); i++)
            _MiniPostRow(text: _dummyPosts[i], index: i),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MiniPostRow extends StatelessWidget {
  const _MiniPostRow({required this.text, required this.index});

  final String text;
  final int index;

  static const _handles = ['ghost_301', 'silent_owl', 'byte_lens'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _handles[index % _handles.length],
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: AppColors.coral,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LEADERBOARD SECTION
// ---------------------------------------------------------------------------

class _LeaderboardSection extends StatelessWidget {
  const _LeaderboardSection({
    required this.entries,
    required this.communityLabel,
    required this.scrollCtrl,
    required this.bottomPad,
  });

  final List<_LeaderEntry> entries;
  final String communityLabel;
  final ScrollController scrollCtrl;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    final myEntry = entries.where((e) => e.isMe).firstOrNull;

    return ListView(
      controller: scrollCtrl,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 96),
      children: [
        // Header card
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Top Engaged This Week',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    communityLabel,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: AppColors.coral,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.coral.withValues(alpha: 0.30),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Resets in',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      '2d 14h',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        color: AppColors.coral,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // My rank callout (if ranked)
        if (myEntry != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.coral.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Your rank',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  '#${myEntry.rank}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 20,
                    color: AppColors.coral,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${myEntry.score} pts',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Podium (top 3)
        _Podium(top3: entries.take(3).toList()),

        const SizedBox(height: 16),

        // Ranked list (4+)
        for (final entry in entries.skip(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _LeaderRow(entry: entry),
          ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top3});

  final List<_LeaderEntry> top3;

  @override
  Widget build(BuildContext context) {
    if (top3.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // #2
          if (top3.length > 1)
            Expanded(child: _PodiumSlot(entry: top3[1], height: 80)),
          const SizedBox(width: 8),
          // #1
          Expanded(
            child: _PodiumSlot(
              entry: top3[0],
              height: 108,
              isFirst: true,
            ),
          ),
          const SizedBox(width: 8),
          // #3
          if (top3.length > 2)
            Expanded(child: _PodiumSlot(entry: top3[2], height: 60)),
        ],
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({
    required this.entry,
    required this.height,
    this.isFirst = false,
  });

  final _LeaderEntry entry;
  final double height;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final medals = ['🥇', '🥈', '🥉'];
    final medal = entry.rank <= 3 ? medals[entry.rank - 1] : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFirst)
          Text('👑', style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        ScoreGlowRing(
          score: entry.score,
          size: isFirst ? 44 : 36,
          borderWidth: isFirst ? 2.0 : 1.5,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                entry.handle[0].toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: isFirst ? 16 : 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          medal,
          style: TextStyle(fontSize: isFirst ? 16 : 14),
        ),
        const SizedBox(height: 2),
        Text(
          entry.handle,
          style: GoogleFonts.jetBrainsMono(
            fontSize: isFirst ? 10 : 9,
            color: entry.isMe ? AppColors.coral : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${entry.score}',
          style: GoogleFonts.jetBrainsMono(
            fontSize: isFirst ? 13 : 11,
            color: AppColors.coral,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: entry.rank == 1
                ? AppColors.coral.withValues(alpha: 0.18)
                : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: entry.rank == 1
                  ? AppColors.coral.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Center(
            child: Text(
              '#${entry.rank}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: entry.rank == 1
                    ? AppColors.coral
                    : AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.entry});

  final _LeaderEntry entry;

  @override
  Widget build(BuildContext context) {
    final maxScore = 342.0; // top score for bar width calc
    final barFraction = (entry.score / maxScore).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: entry.isMe
            ? AppColors.coral.withValues(alpha: 0.08)
            : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.isMe
              ? AppColors.coral.withValues(alpha: 0.30)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              '#${entry.rank}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: entry.isMe ? AppColors.coral : AppColors.textMuted,
                fontWeight:
                    entry.isMe ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),

          // Avatar
          ScoreGlowRing(
            score: entry.score,
            size: 28,
            borderWidth: 1.2,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  entry.isMe ? 'ME' : entry.handle[0].toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: entry.isMe ? AppColors.coral : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Handle + score bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.isMe ? 'you' : entry.handle,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: entry.isMe
                        ? AppColors.coral
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      Container(
                        height: 3,
                        width: constraints.maxWidth,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        height: 3,
                        width: constraints.maxWidth * barFraction,
                        decoration: BoxDecoration(
                          color: entry.isMe
                              ? AppColors.coral
                              : AppColors.textMuted.withValues(alpha: 0.60),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Score + delta
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${entry.score}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: entry.isMe ? AppColors.coral : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    entry.delta >= 0
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 8,
                    color: entry.delta >= 0
                        ? const Color(0xFF4ADE80)
                        : AppColors.coral,
                  ),
                  Text(
                    '${entry.delta.abs()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: entry.delta >= 0
                          ? const Color(0xFF4ADE80)
                          : AppColors.coral,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
