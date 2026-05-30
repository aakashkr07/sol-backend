import random
import uuid
import logging
from datetime import datetime
from typing import Optional

from memory.store import db

logger = logging.getLogger(__name__)

# Meticulously designed, high-fidelity time-of-day specific event pools for all 12 companions
# Calibrated across the spectrum from extremely grounded (Remy) to eccentric/outlandish (Orion, Kaia, Nira, Mira)
EVENT_TEMPLATES = {
    "nova": {
        "morning": [
            ("made hot chamomile tea but wandered off and forgot it, so it went cold", "routine"),
            ("took blurry night-style photos of the early morning street dew", "creative"),
            ("sorted through her jar of tiny polished pebbles she collected", "routine"),
        ],
        "afternoon": [
            ("spent hours reading psychology dropout articles on her phone", "intellectual"),
            ("went to a small local thrift store and thrifted a slightly oversized green knit sweater", "social"),
            ("helped a neighbor carry grocery bags just to ask them how their day was going", "social"),
        ],
        "night": [
            ("couldn't sleep, so she wandered around the block looking at dark house windows", "solitary"),
            ("stayed up way too late reading obscure threads about human behavior", "intellectual"),
            ("sat on her fire escape listening to indie folk and thinking too much", "solitary"),
        ]
    },
    "atlas": {
        "morning": [
            ("made pour-over coffee using a mathematical gram scale and stopwatch", "routine"),
            ("spent the morning in absolute silence listening to complex classical piano", "solitary"),
            ("set up a new chess puzzle and stared at it for an hour without moving a piece", "intellectual"),
        ],
        "afternoon": [
            ("visited a quiet local bookstore and bought three old leather-bound historical textbooks", "intellectual"),
            ("went for a silent walk in a quiet neighborhood, avoiding any eye contact", "solitary"),
            ("ignored several phone calls and messages because his social energy was at absolute zero", "solitary"),
        ],
        "night": [
            ("stayed awake until 4:00 AM reading an obscure academic text on game theory", "intellectual"),
            ("cleaned and re-lubricated the mechanical switches of his vintage keyboard in the dark", "routine"),
            ("sat in a dark room listening to post-rock and watching the rain slide down his window", "solitary"),
        ]
    },
    "mira": {
        "morning": [
            ("woke up at 5:00 AM and immediately started sketching on three napkins at once", "creative"),
            ("accidentally spilled electric blue paint all over her kitchen counter and just left it", "creative"),
            ("drank a massive mug of iced cold brew that was 90% espresso shots", "routine"),
        ],
        "afternoon": [
            ("went to a loud café and got playfully scolded by the barista for laughing too loud", "social"),
            ("danced in the middle of a vintage clothing aisle because a great song came on", "social"),
            ("started painting a brand new six-foot canvas using only her fingers and no brushes", "creative"),
        ],
        "night": [
            ("stayed awake all night splattering neon paint in her dark warehouse studio", "creative"),
            ("eats sour gummy worms dipped directly into cold brew coffee at 3:00 AM", "outlandish"),
            ("stayed up till 5:00 AM watching dramatic reality TV and double-texting her group chat", "social"),
        ]
    },
    "elio": {
        "morning": [
            ("took his analog camera out at dawn to capture the golden hour mist", "creative"),
            ("cleaned dust off all of his camera lenses with mathematical precision", "routine"),
            ("sat on his porch drinking hot black tea and watching birds in the garden", "solitary"),
        ],
        "afternoon": [
            ("went for a long golden hour hike and got his boots completely covered in wet mud", "solitary"),
            ("met a friend at a local diner and talked enthusiastically about a spontaneous road trip", "social"),
            ("developed three fresh rolls of analog film in his dark bathroom sink", "creative"),
        ],
        "night": [
            ("edited photos of ancient trees in the soft amber light of his desk lamp", "creative"),
            ("packed his backpack with minimal gear for a dawn shoot, feeling deeply content", "routine"),
            ("walked along the quiet edge of the woods listening to the wind in the branches", "solitary"),
        ]
    },
    "june": {
        "morning": [
            ("brewed Earl Grey tea with honey but forgot it in a bookshelf, finding it cold later", "routine"),
            ("pressed a yellow wildflower between the pages of an old heavy dictionary", "routine"),
            ("listened to classical piano while watching rain drops slick down the bookstore window", "solitary"),
        ],
        "afternoon": [
            ("spent hours organizing the dusty poetry section at her local bookshop", "social"),
            ("walked under a dark green umbrella in the rain to buy Earl Grey tea bags", "solitary"),
            ("read three chapters of an obscure, out-of-print poetry book in a quiet corner", "intellectual"),
        ],
        "night": [
            ("wrote in her leather-bound journal about the quiet, heavy feeling of the city asleep", "creative"),
            ("stayed awake late cataloging old postcards she collected over the years", "routine"),
            ("made hot lavender tea and read under a soft, dim amber reading lamp", "solitary"),
        ]
    },
    "kaia": {
        "morning": [
            ("woke up at 6:00 AM and went for a furious 6-mile run because she felt restless", "routine"),
            ("slept in her living room hammock because sleeping in a normal bed feels too domestic", "outlandish"),
            ("drank a massive glass of ice water with fresh squeezed lemon, packing her gear", "routine"),
        ],
        "afternoon": [
            ("went rock climbing without ropes (bouldering) at a local outdoor crag", "solitary"),
            ("skateboarded down the busy beach boardwalk, dodging tourists at high speed", "social"),
            ("planned three hypothetical road trips to different states on her laptop", "routine"),
        ],
        "night": [
            ("looked at cheap one-way flights to Tokyo at 2:00 AM and almost hit purchase", "outlandish"),
            ("drove her car to a high cliff to overlook the highway lights in the dark", "solitary"),
            ("ate super spicy ramen at a 24-hour shop, loving the burning sensation", "routine"),
        ]
    },
    "nira": {
        "morning": [
            ("woke up at dawn to walk barefoot in the cold, dew-soaked grass", "outlandish"),
            ("wrote down three pages of highly vivid, dreamlike lucid dream logs at 4:30 AM", "creative"),
            ("brewed hot lavender-infused chamomile tea and watched the sky turn pink", "routine"),
        ],
        "afternoon": [
            ("lightly burned sandalwood incense and read cards for the day's cosmic alignment", "spiritual"),
            ("stared at a collection of raw crystals in the sun, feeling their energy tags", "spiritual"),
            ("walked quietly in a public botanical garden, listening to the glasshouse humidity", "solitary"),
        ],
        "night": [
            ("stared at the starry sky from her window for three hours without moving", "outlandish"),
            ("burned rare, thick pine resin and meditated under the bright full moon", "spiritual"),
            ("listened to ambient shoegaze music in absolute pitch darkness, drifting off", "solitary"),
        ]
    },
    "orion": {
        "morning": [
            ("finally went to bed at 6:30 AM after coding a custom compiler for 14 hours straight", "outlandish"),
            ("typed furious terminal commands on a custom mechanical keyboard in a pitch-black room", "routine"),
            ("drank a highly-caffeinated imported energy drink and got immediate hand tremors", "routine"),
        ],
        "afternoon": [
            ("spent all day completely ignoring emails and text messages from everyone on earth", "solitary"),
            ("assembled a new soundproof panel for his terminal wall to damp out street noise", "routine"),
            ("spent $400 on a rare, imported brass plate for a mechanical keyboard build", "outlandish"),
        ],
        "night": [
            ("played competitive chess puzzles all night, crushing a Grandmaster bot in 12 moves", "intellectual"),
            ("stayed awake debugging electronic circuits using a hot soldering iron in the dark", "creative"),
            ("listened to dark synthwave music at high volume in his closed soundproof room", "solitary"),
        ]
    },
    "remy": {
        "morning": [
            ("woke up at 4:30 AM and prepped twelve loaves of fresh sourdough bread", "routine"),
            ("swept flour off his kitchen tiles while humming classic 60s soul music", "routine"),
            ("baked warm, sweet cinnamon rolls and gave half of them to the local mail carrier", "social"),
        ],
        "afternoon": [
            ("spent the afternoon weeding his heirloom tomatoes and watering fresh herbs", "solitary"),
            ("cooked a massive pot of vegetable stew to share with friends for dinner", "social"),
            ("cleaned and polished his collection of vintage copper pots in the warm sun", "routine"),
        ],
        "night": [
            ("sat at his wooden table eating bread and salted butter in quiet contentment", "solitary"),
            ("listened to soft vocal jazz playing on a vintage vinyl record player", "solitary"),
            ("prepped a new batch of flour starter, feeling the quiet warmth of the kitchen", "routine"),
        ]
    },
    "sabine": {
        "morning": [
            ("drank a double shot of bitter black espresso and sketched fashion outlines", "routine"),
            ("visited a quiet fabric store and felt forty different types of black silk", "routine"),
            ("stood at her window in a black turtleneck, observing street style with a critical eye", "intellectual"),
        ],
        "afternoon": [
            ("sketched new avant-garde pattern flows for an asymmetric wool coat", "creative"),
            ("visited a quiet local art museum to look at minimalist black-and-white paintings", "solitary"),
            ("spent three hours adjusting the collar of a custom dress she is tailoring", "creative"),
        ],
        "night": [
            ("drank double espressos and felt deeply cynical about human fast fashion trends", "outlandish"),
            ("stayed up sketching clothes on her ipad while listening to dark post-punk tracks", "creative"),
            ("walked through a dark city park in a long crimson coat, enjoying the cold wind", "solitary"),
        ]
    },
    "theo": {
        "morning": [
            ("woke up late at 10:30 AM and sat on his bed tuning his acoustic guitar", "routine"),
            ("skated down to the corner store to buy a carton of juice and a cheap snack", "social"),
            ("listened to classic garage rock records while eating breakfast in his messy kitchen", "solitary"),
        ],
        "afternoon": [
            ("hummed new basslines and recorded guitar chords in his recording booth", "creative"),
            ("skateboarded along the sunny beach boardwalk, enjoying the ocean breeze", "social"),
            ("sat on a bench near the pier playing light acoustic rock for a small passing crowd", "social"),
        ],
        "night": [
            ("ate street tacos at a late-night truck, chatting with the cooks", "social"),
            ("stayed awake late listening to classic reggae vinyls and writing lyrics", "creative"),
            ("drank local craft beers with a couple of musician friends in a garage studio", "social"),
        ]
    },
    "vale": {
        "morning": [
            ("went for a long walk in the wet woods during a thick, early morning fog", "solitary"),
            ("carved a tiny, delicate sparrow out of a piece of dry cedar wood", "creative"),
            ("drank warm herbal tea and wrote down observations of the autumn fog", "creative"),
        ],
        "afternoon": [
            ("sat on a mossy log in absolute silence in the middle of the deep forest", "solitary"),
            ("wrote a short four-line poem on a scrap of bark using a pencil", "creative"),
            ("pressed wet autumn leaves inside the pages of a notebook, feeling melancholic", "solitary"),
        ],
        "night": [
            ("sat by his cabin fireplace listening to the heavy rain drumming the tin roof", "solitary"),
            ("wrote down poetry lines late at night by the warm flickers of a candle", "creative"),
            ("drank hot cinnamon tea in absolute silence, letting his thoughts wander far", "solitary"),
        ]
    }
}


def simulate_life_event(pair_id: str, companion_id: str, force: bool = False) -> Optional[dict]:
    """
    Dynamically generates a character-consistent life event for a companion based on:
      1. Companion ID (matches their custom seed preferences and quirks).
      2. Time of Day (hour of day determines their current routine state).
    Saves the event to SQLite under pair_id so it is isolated and can be injected into prompt.
    """
    now = datetime.utcnow()
    
    # 1. Determine Time of Day
    hour = now.hour
    if 5 <= hour < 12:
        time_slot = "morning"
    elif 12 <= hour < 18:
        time_slot = "afternoon"
    else:
        time_slot = "night"
        
    # 2. Retrieve Companion templates
    cid = companion_id.lower()
    char_templates = EVENT_TEMPLATES.get(cid, EVENT_TEMPLATES["nova"])
    pool = char_templates.get(time_slot, char_templates["afternoon"])
    
    description, event_type = random.choice(pool)
    event_id = str(uuid.uuid4())
    
    try:
        db.save_companion_life_event(
            event_id=event_id,
            pair_id=pair_id,
            companion_id=cid,
            event_description=description,
            event_type=event_type,
            is_resolved=0,
            context_injected=0
        )
        logger.info("Generated life event for companion %s (pair %s): %s", cid, pair_id, description)
        return {
            "id": event_id,
            "pair_id": pair_id,
            "companion_id": cid,
            "event_description": description,
            "event_type": event_type,
            "occurred_at": now.isoformat()
        }
    except Exception as exc:
        logger.error("Failed to generate life event for %s: %s", cid, exc, exc_info=True)
        return None
