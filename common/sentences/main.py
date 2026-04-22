import random
from random import choice

MAX_DEPTH = 3  # control max recursion depth here

# --- Element hierarchy ---

class Element:
    pass

class Word(Element):
    def __init__(self, word):
        self.word = word
    def __repr__(self):
        return self.word

class NounPhrase(Element):
    def __init__(self, *parts):
        self.parts = parts
    def __repr__(self):
        return " ".join(str(p) for p in self.parts)

class VerbPhrase(Element):
    def __init__(self, *parts):
        self.parts = parts
    def __repr__(self):
        return " ".join(str(p) for p in self.parts)

class PrepPhrase(Element):
    def __init__(self, *parts):
        self.parts = parts
    def __repr__(self):
        return " ".join(str(p) for p in self.parts)

class AdjPhrase(Element):
    def __init__(self, *parts):
        self.parts = parts
    def __repr__(self):
        return " ".join(str(p) for p in self.parts)

class AdvPhrase(Element):
    def __init__(self, *parts):
        self.parts = parts
    def __repr__(self):
        return " ".join(str(p) for p in self.parts)

class Sentence(Element):
    def __init__(self, *parts):
        self.parts = parts
    def __repr__(self):
        s = " ".join(str(p) for p in self.parts)
        return s[0].upper() + s[1:] + "."

# --- lexicon ---

NOUNS = [
    {"word": "dog",      "number": "singular"},
    {"word": "cat",      "number": "singular"},
    {"word": "car",      "number": "singular"},
    {"word": "apple",    "number": "singular"},
    {"word": "idea",     "number": "singular"},
    {"word": "students", "number": "plural"},
    {"word": "cars",     "number": "plural"},
    {"word": "trees",    "number": "plural"},
]

ADJS  = ["big", "small", "strange", "fast", "ancient", "weird"]
ADVS  = ["quickly", "slowly", "silently", "badly", "barely"]

VERBS = [
    {"base": "eat",     "3sg": "eats"},
    {"base": "see",     "3sg": "sees"},
    {"base": "like",    "3sg": "likes"},
    {"base": "build",   "3sg": "builds"},
    {"base": "destroy", "3sg": "destroys"},
]

PROPER_NOUNS  = ["John", "Sarah", "London", "Birmingham", "NASA"]
PREPS         = ["in", "on", "under", "over", "with", "near"]
INTERJECTIONS = ["wow", "hey", "oh", "damn"]
AUX           = ["is", "was", "will", "can"]

DETS_SINGULAR = ["the", "this", "that", "my", "your"]
DETS_PLURAL   = ["the", "these", "those", "my", "your"]

# --- helpers ---

def starts_with_vowel_sound(word: str) -> bool:
    return word[0].lower() in "aeiou"

def get_det(noun_entry: dict) -> Word:
    if noun_entry["number"] == "plural":
        return Word(random.choice(DETS_PLURAL))
    if random.random() < 0.4:
        return Word("an" if starts_with_vowel_sound(noun_entry["word"]) else "a")
    return Word(random.choice(DETS_SINGULAR))

# --- leaf generators ---

def gen_noun_word():
    entry = random.choice(NOUNS)
    return Word(entry["word"]), entry          # word + metadata

def gen_adj():        return Word(random.choice(ADJS))
def gen_adv():        return Word(random.choice(ADVS))
def gen_verb():       return Word(random.choice(VERBS)["base"])
def gen_aux():        return Word(random.choice(AUX))
def gen_prep():       return Word(random.choice(PREPS))
def gen_proper_noun():return Word(random.choice(PROPER_NOUNS))
def gen_interjection():return Word(random.choice(INTERJECTIONS))

# --- phrase generators (depth-limited) ---

def gen_noun_phrase(depth=0) -> NounPhrase:
    r = random.random()
    # At max depth, only produce simple forms (no recursive prep phrase)
    if depth >= MAX_DEPTH or r > 0.5:
        noun_word, entry = gen_noun_word()
        det = get_det(entry)
        return NounPhrase(det, noun_word)
    elif r > 0.3:
        noun_word, entry = gen_noun_word()
        det = get_det(entry)
        return NounPhrase(det, gen_adj(), noun_word)
    elif r > 0.05:
        return NounPhrase(gen_proper_noun())
    else:
        # recursive: NP -> NP + PP
        return NounPhrase(gen_noun_phrase(depth + 1), gen_prep_phrase(depth + 1))

def gen_verb_phrase(depth=0) -> VerbPhrase:
    options = [
        lambda: VerbPhrase(gen_verb()),
        lambda: VerbPhrase(gen_verb(), gen_noun_phrase(depth + 1)),
        lambda: VerbPhrase(gen_verb(), gen_noun_phrase(depth + 1), gen_noun_phrase(depth + 1)),
        lambda: VerbPhrase(gen_verb(), gen_prep_phrase(depth + 1)),
        lambda: VerbPhrase(gen_verb(), gen_noun_phrase(depth + 1), gen_prep_phrase(depth + 1)),
        lambda: VerbPhrase(gen_aux(), gen_verb()),
        lambda: VerbPhrase(gen_verb(), gen_adv_phrase(depth + 1)),
    ]
    # At max depth, only allow simple verb (no recursive sub-phrases)
    if depth >= MAX_DEPTH:
        return VerbPhrase(gen_verb())
    return choice(options)()

def gen_prep_phrase(depth=0) -> PrepPhrase:
    return PrepPhrase(gen_prep(), gen_noun_phrase(depth + 1))

def gen_adj_phrase(depth=0) -> AdjPhrase:
    if depth >= MAX_DEPTH:
        return AdjPhrase(gen_adj())
    return choice([
        lambda: AdjPhrase(gen_adj()),
        lambda: AdjPhrase(gen_adv(), gen_adj()),
    ])()

def gen_adv_phrase(depth=0) -> AdvPhrase:
    if depth >= MAX_DEPTH:
        return AdvPhrase(gen_adv())
    return choice([
        lambda: AdvPhrase(gen_adv()),
        lambda: AdvPhrase(gen_adv(), gen_adv()),
    ])()

# --- sentence generator ---

def gen_sentence() -> Sentence:
    r = random.random()
    if r > 0.5:
        return Sentence(gen_noun_phrase(), gen_verb_phrase())
    elif r > 0.3:
        return Sentence(gen_noun_phrase(), gen_verb_phrase(), gen_prep_phrase())
    elif r > 0.05:
        return Sentence(gen_noun_phrase(), gen_verb_phrase(), gen_adv_phrase())
    else:
        return Sentence(gen_interjection())

# --- main ---

if __name__ == "__main__":
    for _ in range(10):
        print(gen_sentence())
