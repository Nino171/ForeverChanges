"""Generate SpellData.lua: spells that are new to, or changed in, WoW: Forever compared with Classic Era.

Reads the DB2 tables from wago.tools (downloaded once into a cache folder) and writes ../SpellData.lua.

    python tools/make_spell_data.py [forever_build] [era_build]

Classic Era's client data also contains Season of Discovery spells (IDs from 400000 up); those are
not original Classic, so they count as new.
"""
import collections
import csv
import difflib
import os
import re
import sys
import tempfile
import urllib.request

FOREVER_BUILD = "1.60.1.70124"
ERA_BUILD = "1.15.9.70003"
TABLES = ["SpellName", "Spell", "SpellMisc", "SpellEffect", "SpellPower", "SpellCooldowns", "SpellAuraOptions",
          "SpellTargetRestrictions", "SpellShapeshift", "SkillLineAbility", "SkillLine", "SpellCastTimes",
          "SpellDuration", "SpellRange", "SpellRadius"]
MAX_VANILLA_ID = 400000
SKILL_CATEGORIES = {"6", "7", "8", "9", "10", "11"}  # weapons, class, armor, secondary, languages, professions
SKIP_SKILLS = {"Engraving", "Runes"}
POWER_NAMES = {0: "Mana", 1: "Rage", 2: "Focus", 3: "Energy"}
WARRIOR_STANCES = {65536: "Battle Stance", 131072: "Defensive Stance", 262144: "Berserker Stance"}
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SpellData.lua")

csv.field_size_limit(10 ** 9)


def fnum(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return 0.0


def clean_num(v):
    if abs(v - round(v)) < 0.005:
        return str(int(round(v)))
    return ("%.2f" % v).rstrip("0").rstrip(".")


def fmt_duration(ms):
    s = ms / 1000.0
    if s < 60:
        return clean_num(s) + " sec"
    if s < 3600:
        return clean_num(s / 60.0) + " min"
    hours = s / 3600.0
    return clean_num(hours) + (" hour" if abs(hours - 1) < 0.005 else " hours")


def load(cache, table, build):
    path = os.path.join(cache, "%s.%s.csv" % (table, build))
    if not os.path.exists(path):
        url = "https://wago.tools/db2/%s/csv?build=%s" % (table, build)
        print("downloading", url)
        req = urllib.request.Request(url, headers={"User-Agent": "forever-quest-tint"})
        with urllib.request.urlopen(req) as r, open(path, "wb") as out:
            out.write(r.read())
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def group(rows, key):
    out = collections.defaultdict(list)
    for r in rows:
        out[int(r[key])].append(r)
    return out


def by_id(rows):
    return {int(r["ID"]): r for r in rows}


class Build:
    def __init__(self, cache, build, forever):
        t = {name: load(cache, name, build) for name in TABLES}
        self.forever = forever
        self.name = {int(r["ID"]): r["Name_lang"] for r in t["SpellName"]}
        self.spell = by_id(t["Spell"])
        self.misc = group(t["SpellMisc"], "SpellID")
        self.effect = group(t["SpellEffect"], "SpellID")
        self.power = group(t["SpellPower"], "SpellID")
        self.cooldown_rows = group(t["SpellCooldowns"], "SpellID")
        self.aura = group(t["SpellAuraOptions"], "SpellID")
        self.target = group(t["SpellTargetRestrictions"], "SpellID")
        self.shape = group(t["SpellShapeshift"], "SpellID")
        self.sla = group(t["SkillLineAbility"], "Spell")
        self.skill = by_id(t["SkillLine"])
        self.cast = by_id(t["SpellCastTimes"])
        self.dur = by_id(t["SpellDuration"])
        self.range = by_id(t["SpellRange"])
        self.radius = by_id(t["SpellRadius"])
        self._cache = {}

    # ---- structured facts ----------------------------------------------
    def effects(self, sid):
        return {int(e["EffectIndex"]) + 1: e for e in self.effect.get(sid, []) if e["DifficultyID"] == "0"}

    def eff_range(self, e):
        """(min, max) of an effect as a tooltip shows it. Era stores base points + die sides, Forever an average + variance."""
        if self.forever:
            avg, var = fnum(e["EffectBasePointsF"]), fnum(e["Variance"])
            if var > 0:
                d = abs(avg) * var / 2
                return round(avg - d), round(avg + d)
            return avg, avg
        base, die = int(fnum(e["EffectBasePoints"])), int(fnum(e["EffectDieSides"]))
        return (base + 1, base + die) if die > 1 else (base + 1, base + 1)

    def radius_yd(self, e):
        r = self.radius.get(int(e["EffectRadiusIndex_0"]))
        return fnum(r["Radius"]) if r else 0.0

    def first_misc(self, sid):
        rows = self.misc.get(sid)
        return rows[0] if rows else None

    def duration_ms(self, sid):
        m = self.first_misc(sid)
        d = self.dur.get(int(m["DurationIndex"])) if m else None
        return int(fnum(d["Duration"])) if d else 0

    def cast_ms(self, sid):
        m = self.first_misc(sid)
        c = self.cast.get(int(m["CastingTimeIndex"])) if m else None
        return int(fnum(c["Base"])) if c else 0

    def range_yd(self, sid):
        m = self.first_misc(sid)
        r = self.range.get(int(m["RangeIndex"])) if m else None
        return max(fnum(r["RangeMax_0"]), fnum(r["RangeMax_1"])) if r else 0.0

    def cooldown_ms(self, sid):
        rows = [c for c in self.cooldown_rows.get(sid, []) if c["DifficultyID"] == "0"]
        if not rows:
            return 0
        # The two builds put the same cooldown in different columns.
        return max(int(fnum(rows[0]["RecoveryTime"])), int(fnum(rows[0]["CategoryRecoveryTime"])))

    def costs(self, sid):
        out = []
        for p in self.power.get(sid, []):
            ptype = int(fnum(p["PowerType"]))
            if ptype not in POWER_NAMES:
                continue  # combo points and the like are not a cost in vanilla
            flat = round(fnum(p["ManaCost"]))
            if ptype == 1:
                flat //= 10  # rage is stored times ten
            pct = round(fnum(p["PowerCostPct"]), 1)
            if flat or pct:
                out.append((ptype, flat, pct))
        return sorted(out)

    def proc(self, sid):
        rows = [a for a in self.aura.get(sid, []) if a["DifficultyID"] == "0"]
        if not rows:
            return 0, 0
        chance = int(fnum(rows[0]["ProcChance"]))
        return (0 if chance in (0, 101) else chance), int(fnum(rows[0]["ProcCharges"]))

    def max_targets(self, sid):
        rows = [t for t in self.target.get(sid, []) if t["DifficultyID"] == "0"]
        return int(fnum(rows[0]["MaxTargets"])) if rows else 0

    def stance_mask(self, sid):
        rows = self.shape.get(sid, [])
        return int(fnum(rows[0]["ShapeshiftMask_0"])) if rows else 0

    # ---- description templates -------------------------------------------
    def value(self, sid, letter, idx, other=None):
        """(number, display text) for a $-token; KeyError if it is not supported."""
        target = other or sid
        e = self.effects(target).get(idx or 1)
        if letter in "smMwSW":
            if not e:
                raise KeyError
            lo, hi = (abs(v) for v in self.eff_range(e))
            if letter in "mw":
                return lo, clean_num(lo)
            if letter == "M":
                return hi, clean_num(hi)
            if lo != hi:
                lo, hi = min(lo, hi), max(lo, hi)
                return lo, clean_num(lo) + " to " + clean_num(hi)
            return lo, clean_num(lo)
        if letter == "o":
            period, dur = (int(fnum(e["EffectAuraPeriod"])) if e else 0), self.duration_ms(target)
            if not period or not dur:
                raise KeyError
            lo, hi = (abs(v) * dur / period for v in self.eff_range(e))
            if round(lo) != round(hi):
                return lo, clean_num(round(lo)) + " to " + clean_num(round(hi))
            return lo, clean_num(round(lo))
        if letter == "d":
            ms = self.duration_ms(target)
            return ms / 1000.0, fmt_duration(ms)
        if letter == "t":
            if not e:
                raise KeyError
            p = int(fnum(e["EffectAuraPeriod"])) / 1000.0
            return p, clean_num(p)
        if letter == "a":
            if not e:
                raise KeyError
            r = self.radius_yd(e)
            return r, clean_num(r)
        if letter == "x":
            if not e:
                raise KeyError
            c = fnum(e["EffectChainTargets"])
            return c, clean_num(c)
        if letter == "h":
            p = self.proc(target)[0] or 100
            return p, str(p)
        if letter == "n":
            c = self.proc(target)[1]
            return c, str(c)
        if letter == "i":
            c = self.max_targets(target)
            return c, str(c)
        if letter == "r":
            r = self.range_yd(target)
            return r, clean_num(r)
        raise KeyError

    def resolve(self, sid, field="Description_lang", depth=0):
        """Description with its $-tokens filled in: (text, fully_resolved)."""
        key = (sid, field)
        if key not in self._cache:
            sp = self.spell.get(sid)
            self._cache[key] = self._fill(sid, sp[field] if sp else "", depth)
        return self._cache[key]

    def _fill(self, sid, text, depth):
        ok = [True]
        last = [1.0]  # the previous number, for $l singular:plural;
        text = strip_conditionals(text)

        def parse(s):
            m = re.fullmatch(r"\$([/*])(-?\d+);(\d*)([a-zA-Z])(\d?)", s)
            if m:
                op, n, other, letter, idx = m.groups()
                v, _ = self.value(sid, letter, int(idx) if idx else None, int(other) if other else None)
                return (v / float(n) if op == "/" else v * float(n)), None
            m = re.fullmatch(r"\$(\d*)([a-zA-Z])(\d?)", s)
            if m:
                other, letter, idx = m.groups()
                return self.value(sid, letter, int(idx) if idx else None, int(other) if other else None)
            raise KeyError

        def expression(m):
            try:
                body = re.sub(VALUE_TOKEN, lambda t: "(%r)" % parse(t.group(0))[0], m.group(1))
                if not re.fullmatch(r"[0-9+\-*/(). eE]*", body):
                    raise KeyError
                v = eval(body, {"__builtins__": {}}, {})
            except (KeyError, SyntaxError, ZeroDivisionError, TypeError):
                ok[0] = False
                return ""
            last[0] = v
            return ("%." + m.group(2) + "f") % v if m.group(2) else clean_num(v)

        def token(m):
            s = m.group(0)
            if s.startswith("${"):
                return expression(re.fullmatch(r"\$\{([^{}]*)\}(?:\.(\d+))?", s))
            p = re.fullmatch(r"\$[lL]([^:;$]*):([^;$]*);", s)
            if p:
                return p.group(1) if last[0] == 1 else p.group(2)
            g = re.fullmatch(r"\$g([^:;$]*):([^;$]*);", s)
            if g:
                return g.group(1)
            ref = re.fullmatch(r"\$@(spelldesc|spellname|spellicon)(\d+)", s)
            if ref:
                kind, other = ref.group(1), int(ref.group(2))
                if kind == "spellicon":
                    return ""
                if kind == "spellname":
                    return self.name.get(other, "")
                if depth > 3:
                    ok[0] = False
                    return ""
                t, o = self.resolve(other, "Description_lang", depth + 1)
                ok[0] = ok[0] and o
                return t
            try:
                v, txt = parse(s)
            except KeyError:
                ok[0] = False
                return ""
            last[0] = v
            return clean_num(v) if txt is None else txt

        out = re.sub(r"\$\{[^{}]*\}(?:\.\d+)?|\$[lLg][^:;$]*:[^;$]*;|" + VALUE_TOKEN + r"|\$@[a-z]+\d*", token, text)
        if "$" in out:
            ok[0] = False
        return re.sub(r"\|[cC][0-9a-fA-F]{8}|\|[rR]", "", out), ok[0]


VALUE_TOKEN = r"\$[/*]-?\d+;\d*[a-zA-Z]\d?|\$\d*[a-zA-Z]\d?(?![a-zA-Z])"


def strip_conditionals(text):
    """$?cond[then][else]: the player is assumed to know none of the spells/auras a condition names."""
    while True:
        i = text.find("$?")
        if i < 0:
            return text

        def grab(pos):
            depth = 0
            for q in range(pos, len(text)):
                if text[q] == "[":
                    depth += 1
                elif text[q] == "]":
                    depth -= 1
                    if depth == 0:
                        return text[pos + 1:q], q + 1
            return text[pos + 1:], len(text)

        j, branches, else_body = i + 2, [], ""
        while True:
            k = text.find("[", j)
            if k < 0:
                return text[:i] + text[j:]
            cond = text[j:k]
            body, j = grab(k)
            branches.append((cond, body))
            if j < len(text) and text[j] == "?":
                j += 1
                continue
            if j < len(text) and text[j] == "[":
                else_body, j = grab(j)
            break
        chosen = else_body
        for cond, body in branches:
            c = re.sub(r"[a-zA-Z]+\d*[a-zA-Z]*", "False", cond)
            c = c.replace("!", " not ").replace("&", " and ").replace("|", " or ")
            try:
                truth = bool(eval(c, {"__builtins__": {}}, {}))
            except Exception:
                truth = False
            if truth:
                chosen = body
                break
        text = text[:i] + chosen + text[j:]


# ---- comparison ----------------------------------------------------------------
def words(t):
    t = re.sub(r"[^a-z0-9%. ]", " ", t.lower())
    t = re.sub(r"(?<!\d)\.(?!\d)", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def shape(t):
    t = re.sub(r"\$\{.*?\}|\$\S*", "$", t.lower())
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9$%. ]", " ", t)).strip()


def numbers(t):
    return [float(x) for x in re.findall(r"\d+(?:\.\d+)?", t)]


def text_differs(a, b):
    if a == b:
        return False
    if numbers(a) != numbers(b):
        return True
    return difflib.SequenceMatcher(None, a, b).ratio() < 0.8


# Effects whose base points are a displayed amount (not a script, enchant or item placeholder).
AMOUNT_EFFECTS = {2, 6, 8, 9, 10, 17, 27, 30, 31, 35, 58, 62, 119, 128}


def effect_facts(b, sid):
    out = []
    for idx, e in sorted(b.effects(sid).items()):
        eff = int(fnum(e["Effect"]))
        if eff not in AMOUNT_EFFECTS:
            continue
        lo, hi = (0 if abs(v) <= 1 else round(v) for v in b.eff_range(e))
        out.append((idx, eff, int(fnum(e["EffectAura"])), lo, hi, int(fnum(e["EffectAuraPeriod"])), round(b.radius_yd(e), 1)))
    return out


def compare(era, forever, sid):
    """Returns the changed fields, or an empty list if the spell is the same."""
    fields = []
    for name, fn in (("cast", "cast_ms"), ("cooldown", "cooldown_ms"), ("cost", "costs"), ("range", "range_yd"),
                     ("stance", "stance_mask")):
        a, b = getattr(era, fn)(sid), getattr(forever, fn)(sid)
        if name == "range" and not (a and b):
            continue  # a range of 0 is not shown in the tooltip
        if a != b:
            fields.append(name)
    for name, field in (("desc", "Description_lang"), ("aura", "AuraDescription_lang")):
        (a, a_ok), (b, b_ok) = era.resolve(sid, field), forever.resolve(sid, field)
        if a_ok and b_ok:
            if text_differs(words(a), words(b)):
                fields.append(name)
        else:
            # Some token could not be filled in, so the text can't be compared exactly.
            raw_a, raw_b = era.spell.get(sid, {}).get(field, ""), forever.spell.get(sid, {}).get(field, "")
            if shape(raw_a) != shape(raw_b) or (name == "desc" and effect_facts(era, sid) != effect_facts(forever, sid)):
                fields.append(name + "?")
    return fields


def tidy(text):
    text = re.sub(r"\s*(\r?\n)+\s*", " ", text)
    return re.sub(r" {2,}", " ", text).strip()


def cost_text(costs):
    parts = []
    for ptype, flat, pct in costs:
        if flat:
            parts.append("%d %s" % (flat, POWER_NAMES.get(ptype, "power")))
        if pct:
            parts.append("%s%% of base mana" % clean_num(pct))
    return ", ".join(parts) or "no cost"


def stance_text(era_mask, forever_mask):
    """Only warrior stances are named; other forms are not translated."""
    all_stances = sum(WARRIOR_STANCES)
    if (era_mask | forever_mask) & ~all_stances:
        return None
    if era_mask == 0:
        return "no stance requirement"
    return "requires " + ", ".join(n for bit, n in WARRIOR_STANCES.items() if era_mask & bit)


def vanilla_lines(era, forever, sid, fields):
    """How the spell was in Classic, for the fields that are known to differ; empty if nothing can be said exactly."""
    facts = []
    if "cast" in fields:
        ms = era.cast_ms(sid)
        facts.append("instant cast" if ms == 0 else "%s sec cast" % clean_num(ms / 1000.0))
    if "cost" in fields:
        facts.append(cost_text(era.costs(sid)))
    if "range" in fields:
        yd = era.range_yd(sid)
        if yd > 0:
            facts.append("melee range" if yd <= 5 else "%s yd range" % clean_num(yd))
    if "cooldown" in fields:
        ms = era.cooldown_ms(sid)
        facts.append("no cooldown" if ms == 0 else "%s cooldown" % fmt_duration(ms))
    if "stance" in fields:
        s = stance_text(era.stance_mask(sid), forever.stance_mask(sid))
        if s:
            facts.append(s)
    lines = []
    if facts:
        lines.append("Vanilla: " + ", ".join(facts))
    if "desc" in fields:
        lines.append("Vanilla: " + tidy(era.resolve(sid, "Description_lang")[0]))
    elif "aura" in fields:
        lines.append("Vanilla buff: " + tidy(era.resolve(sid, "AuraDescription_lang")[0]))
    return [l for l in lines if l.split(": ", 1)[1]]


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main():
    forever_build = sys.argv[1] if len(sys.argv) > 1 else FOREVER_BUILD
    era_build = sys.argv[2] if len(sys.argv) > 2 else ERA_BUILD
    cache = os.path.join(tempfile.gettempdir(), "forever-quest-tint-db2")
    os.makedirs(cache, exist_ok=True)
    forever, era = Build(cache, forever_build, True), Build(cache, era_build, False)

    candidates = set()
    for sid, rows in forever.sla.items():
        if sid not in forever.name:
            continue
        for r in rows:
            skill = forever.skill.get(int(r["SkillLine"]))
            if skill and skill["CategoryID"] in SKILL_CATEGORIES and skill["DisplayName_lang"] not in SKIP_SKILLS:
                candidates.add(sid)

    new, changed = [], {}
    for sid in sorted(candidates):
        if sid >= MAX_VANILLA_ID or sid not in era.name:
            new.append(sid)
            continue
        fields = compare(era, forever, sid)
        if not fields:
            continue
        # Only state what is known exactly; fields whose text could not be compared are left out.
        exact = [f for f in fields if not f.endswith("?")]
        changed[sid] = "\n".join(vanilla_lines(era, forever, sid, exact))

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/make_spell_data.py (Forever %s vs Classic Era %s). Do not edit.\n" % (forever_build, era_build))
        f.write("local ADDON, ns = ...\n\n")
        f.write("-- Spells that were not in original Classic.\nns.NewSpells = {\n")
        for i in range(0, len(new), 10):
            f.write("    " + " ".join("[%d]=true," % s for s in new[i:i + 10]) + "\n")
        f.write("}\n\n")
        f.write("-- Spells that changed. The value is how they were in Classic, or true if that is not known exactly.\n")
        f.write("ns.ChangedSpells = {\n")
        for sid in sorted(changed):
            f.write("    [%d]=%s,\n" % (sid, lua_string(changed[sid]) if changed[sid] else "true"))
        f.write("}\n")
    with_text = sum(1 for t in changed.values() if t)
    print("new: %d, changed: %d (%d with vanilla text) -> %s" % (len(new), len(changed), with_text, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
