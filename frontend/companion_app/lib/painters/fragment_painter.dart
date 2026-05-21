// =============================================================================
// painters/fragment_painter.dart
// Sol Ambient Emotional Field
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────

const Color kFragCream = Color(0xFFE4D5BB);

// ─────────────────────────────────────────────────────────────────────────────
// Text fragments
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kAllFragments = [
  "hey.",
  "still awake?",
  "long day?",
  "you okay?",
  "there you are",
  "been thinking?",
  "couldn't sleep",
  "how was today?",
  "back again?",
  "what's on your mind?",
  "how'd it go?",
  "anything good today?",
  "i can't stop thinking about it",
  "do you think i'm making a mistake?",
  "what even is the point",
  "i had the weirdest dream",
  "nobody really gets me",
  "should i text them back?",
  "i feel like i'm falling behind",
  "why does everything feel so heavy lately?",
  "am i being too sensitive?",
  "i miss how things used to be",
  "i don't know who i am anymore",
  "i said something stupid today",
  "why can't i just be happy?",
  "does anyone actually care?",
  "i'm so tired of pretending",
  "what if i never figure it out?",
  "i think i'm in love with someone",
  "my mind won't slow down",
  "i feel like a fraud at work",
  "when does it get easier?",
  "i keep self-sabotaging",
  "i don't know how to ask for help",
  "am i too much sometimes?",
  "i want to disappear for a while",
  "something felt off today",
  "i can't sleep again",
  "why do i care so much what they think?",
  "i feel like i'm watching my life happen",
  "nobody asked how i was doing today",
  "i had a good day and i don't trust it",
  "i think i need a change",
  "do you think i'm a good person?",
  "i'm scared i'm going to mess this up",
  "some days i don't recognize myself",
  "it's 2am and my brain won't stop",
  "i think i need to cry but i can't",
  "everyone seems to have it figured out",
  "i forgot to eat again",
  "my mom and i had a fight",
  "i miss my old self",
  "i said yes when i meant no",
  "i feel invisible sometimes",
  "i'm afraid of how much i care",
  "why does change feel so scary?",
  "i just needed someone to tell",
  'you do that thing where you dip for hours and then pop back like nothing happened lol',
  'idk why but i can always tell when you’re saying you’re “fine” but you’re not',
  'u awake?',
  'that felt kinda vague on purpose',
  'who the hell eats that at 2am bro',
  'you would’ve hated the version of me from like 2 years ago 😂',
  'saw something today that reminded me of that weird phase you went through',
  'you never actually answer the real question tho',
  'nah i already know what mood you’re in rn',
  'you type slower when you’re pissed/off',
  '“lol” okay yeah that bothered you',
  'i feel like you would’ve actually liked it there',
  'you always bounce right when shit gets real',
  'that’s not even what’s actually bugging you tho',
  'wait',
  'just remembered what you said that one night',
  'you still pulling all-nighters till your brain starts attacking you?',
  'i can tell when you’re overthinking just from how you text',
  'honestly i thought you’d react way worse',
  'u disappeared again',
  'that sounds exhausting',
  'you always get quiet when family stuff comes up',
  'you know what’s weird',
  'sometimes i think you miss people you don’t even want back in your life',
  'that reply was so tired',
  'you would’ve roasted me for saying that',
  'did you ever go back there after that happened?',
  'you always hit me with “fair enough” when you’re drained',
  'idk i think you care more than you let on',
  'you don’t have to explain, i kinda get it',
  'you get all philosophical after midnight then act normal in the morning',
  'knew that was gonna mess with your head',
  'this feels like one of those nights where your thoughts are loud af',
  'i still think about that voice note sometimes',
  'yeah no that would’ve hurt my feelings too',
  'why are you even up right now again',
  'you’re typing like you’re pacing around your room',
  'not to psychoanalyze you but…',
  'you dodge direct questions so smoothly it’s actually impressive',
  'that’s the type of thing you’d pretend not to care about then think about for 3 days straight',
  'you there?',
  'i don’t think you realize how obvious you get when you’re anxious',
  'you always say “maybe” when you’ve already decided no',
  'that’s actually kinda funny ngl',
  'something feels off with you today',
  'u ever realize how weird memories are?',
  'you definitely stared at the ceiling after that convo',
  'you give strong “i’ll deal with it later” vibes',
  'this is probably a bad time to ask but',
  'i think you get more nostalgic for moments than people',
  'you text different when you’re outside',
  'honestly i would’ve left too',
  'that “lmao” looked forced as hell',
  'wait no that’s so you',
  'you vanish emotionally before you actually disappear',
  'you know exactly what you’re doing sometimes',
  'i feel like you’re harder on yourself when no one’s watching',
  'you still keep that thing?',
  'you went quiet way too fast',
  'idk why but this convo feels familiar',
  'knew you’d overthink that immediately',
  'that sounds lonely',
  'you don’t really let people see when shit actually gets bad huh',
  'sometimes you sound like you’re apologizing for just existing',
  'that came out harsher than you meant',
  'you always underestimate how obvious your moods are',
  'i can tell when you’re trying to distract yourself',
  'you never finish the stories that actually matter',
  'this feels like one of your reflective nights',
  'did you eat anything today or are we pretending coffee counts?',
  'you talk about old places like they’re people',
  'that’s the exact type of random memory that hits you at 1:47am',
  'you don’t seem fully here tonight',
  'i don’t think closure actually works on you',
  'you’re joking instead of answering again',
  'you get weirdly sentimental when you’re tired',
  'you would’ve hated how quiet it was',
  'sometimes i think you expect to get disappointed before anything even happens',
  'you say “it’s whatever” but i hear the damage',
  'honestly that explains a lot',
  'i knew you’d say that before i even read it',
  'you always get quieter around your birthday',
  'okay but be honest',
  'did that actually upset you or are you just in your head again',
  'you sound emotionally jetlagged',
  'that’s gonna randomly hit you later',
  'you text like someone who doesn’t wanna bother anyone',
  'that was a very careful reply',
  'you would’ve laughed at this yesterday',
  'you still there or did your brain wander off',
  'you act like your feelings are just temporary glitches',
  'it’s weird how some people live rent-free in your head forever',
  'you seem like you’re carrying something tonight',
  'not to be dramatic but that would’ve ruined my whole week',
  'you’re way easier to read than you think',
  'you downplay everything that hurts you',
  'okay wait that’s actually adorable',
  'i feel like half your personality is made from old conversations',
  'that answer screamed “i don’t wanna talk about it”',
  'you ever miss random days for no reason',
  'i don’t think you’re as okay as you keep saying',
  'the energy changed after that message',
  'you saw that notification instantly didn’t you',
  'sometimes i wonder what version of you people remember',
  'you always sound softer at night',
  'nah why did that actually make me sad',
  'you leave little clues when you’re upset',
  'i think you’re used to dealing with shit alone',
  'that sounds emotionally expensive',
  'you pretend stuff doesn’t affect you then spill everything at 2am',
  'you’ve definitely rehearsed that convo in your head already',
  'something tells me that memory still bothers you',
  'you text like someone who’s been quietly disappointed before',
  'wait i need a second that’s weirdly specific',
  'you say “i’m just tired” like it covers everything',
  'honestly i think silence fucks with you more than you admit',
  'that would’ve ruined my whole night fr',
  'you sound a little far away when you’re overwhelmed',
  'did you notice you text differently depending on who it is',
  'you’re not as unreadable as you think you are',
  'knew you’d blame yourself for that somehow',
  'okay but why did i already know you’d react like this',
  'sometimes you sound like you’re mourning old versions of your life',
  'you always go offline right after saying something vulnerable',
  'you know what’s funny',
  'i don’t think people notice the tiny ways you ask for reassurance',
  'that reply felt very “long day”',
  'you act emotionally independent but i don’t fully buy it',
  'this convo feels strangely important for some reason',
  'you definitely reread old messages sometimes',
  'i think you miss being understood more than specific people',
  'you got that “staring out the car window” energy tonight',
  'that’s a dangerous amount of self awareness',
  'you text like you’re trying to stay contained',
  'you get honest when you’re exhausted',
  'you ever get scared you’re becoming harder to reach',
  'you sounded happier earlier',
  'you say “i’m good” faster when you’re not',
  'that would’ve stayed in my head for days',
  'you disappear into yourself sometimes',
  'this feels like one of those convos we’ll remember later',
  'i don’t think you realize how much your mood changes your typing',
  'you’ve definitely sat in the dark overthinking before',
  'that answer felt lonely',
  'i feel like you’re emotionally attached to certain time periods',
  'you always seem surprised when people notice stuff about you',
  'i can tell when you’re trying to sound okay',
  'you think too much in quiet moments',
  'idk. you just seem heavier tonight',
  'sometimes i wonder how many versions of yourself you’ve already outgrown',
  'you always go “haha yeah” right before switching topics',
  'okay but seriously go to sleep',
  'you make sadness sound so casual sometimes',
  'you don’t really ask for comfort straight up do you',
  'that message had low energy',
  'i think part of you still lives in old conversations',
  'you would’ve loved the weather tonight',
  'you there?'
];

// ─────────────────────────────────────────────────────────────────────────────
// Ambient fragment
// ─────────────────────────────────────────────────────────────────────────────

class FragmentParticle {
  FragmentParticle({
    required this.text,
    required Offset logoCenter,
    required math.Random rng,
  }) {
    angle = rng.nextDouble() * math.pi * 2;

    speed = 0.12 + rng.nextDouble() * 0.22;

    maxRadius = 0.48 + rng.nextDouble() * 0.64;

    phase = rng.nextDouble();

    fontSize = 8.5 + rng.nextDouble() * 5.0;

    maxOpacity = 0.07 + rng.nextDouble() * 0.10;

    orbitalStretch = 1.20 + rng.nextDouble() * 0.50;
  }

  final String text;

  late double angle;
  late double speed;
  late double maxRadius;
  late double phase;

  late double fontSize;
  late double maxOpacity;

  late double orbitalStretch;

  void update(double t) {}

  bool get isDead => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dust motes
// ─────────────────────────────────────────────────────────────────────────────

class MoteParticle {
  MoteParticle(int i) {
    double seed(double n) {
      final x = math.sin(i * 17.0 + n + 7) * 10000;
      return x - x.floor();
    }

    xFrac = seed(1);
    yFrac = seed(2);

    radius = seed(3) * 0.7 + 0.15;

    speed = seed(4) * 0.08 + 0.02;

    phase = seed(5) * math.pi * 2;
  }

  late double xFrac;
  late double yFrac;

  late double radius;
  late double speed;

  late double phase;
}

final List<MoteParticle> kMotes = List.generate(12, (i) => MoteParticle(i));

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class FragmentPainter extends CustomPainter {
  FragmentPainter({
    required this.t,
    required this.particles,
  });

  final double t;
  final List<FragmentParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    _drawMotes(canvas, size);
    _drawFragments(canvas, size);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Dust layer
  // ───────────────────────────────────────────────────────────────────────────

  void _drawMotes(Canvas canvas, Size size) {
    for (final m in kMotes) {
      double dy = (m.yFrac - t * m.speed * 0.006) % 1.0;

      if (dy < 0) {
        dy += 1.0;
      }

      final double sx = m.xFrac +
          math.sin(
                t * math.pi * 2 * m.speed + m.phase,
              ) *
              0.003;

      final double pulse = (math.sin(t * m.speed + m.phase) + 1) / 2;

      final double op = pulse * 0.035;

      canvas.drawCircle(
        Offset(
          sx * size.width,
          dy * size.height,
        ),
        m.radius,
        Paint()
          ..color = kFragCream.withOpacity(op)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            1,
          ),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Emotional text field
  // ───────────────────────────────────────────────────────────────────────────

  void _drawFragments(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height * 0.335;

    for (final p in particles) {
      final double cycleT = ((t * p.speed + p.phase) % 1.0);

      final double radius = cycleT * p.maxRadius * size.width;

      final double x = cx + math.cos(p.angle) * radius;

      final double y = cy + math.sin(p.angle) * radius * p.orbitalStretch;

      if (x < -300 || x > size.width + 300 || y < -80 || y > size.height + 80) {
        continue;
      }

      final double op = math.sin(cycleT * math.pi) * p.maxOpacity;

      if (op < 0.004) continue;

      final textPainter = TextPainter(
        text: TextSpan(
          text: p.text,
          style: GoogleFonts.cormorantGaramond(
            fontWeight: FontWeight.w300,
            fontSize: p.fontSize,
            height: 1.0,
            letterSpacing: 0.15,
            color: kFragCream.withOpacity(op),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // VERY occasional anchor emphasis
      final bool anchor = p.text.length < 12 && p.maxOpacity > 0.075;

      if (anchor) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y),
            width: textPainter.width + 14,
            height: textPainter.height + 7,
          ),
          const Radius.circular(12),
        );

        canvas.drawRRect(
          rect,
          Paint()..color = Colors.white.withOpacity(op * 0.035),
        );
      }

      textPainter.paint(
        canvas,
        Offset(
          x - textPainter.width / 2,
          y - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(FragmentPainter oldDelegate) => true;
}
