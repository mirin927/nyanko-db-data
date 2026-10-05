"""Keep the original eight talent slots readable by build 1 without dropping new slots."""
SLOT_WIDTH = 14
LEGACY_LENGTH = 1 + 8 * SLOT_WIDTH
MAX_SLOTS = 64

def normalize_talents(form):
    raw = form['talentData']
    if (not isinstance(raw, list) or any(type(value) is not int for value in raw)
            or (raw and (len(raw) < 1 + SLOT_WIDTH or (len(raw) - 1) % SLOT_WIDTH
                         or len(raw) > 1 + MAX_SLOTS * SLOT_WIDTH))):
        raise ValueError(f"Invalid talent slot layout: {form.get('name', '')}")
    if form.get('talent', 0) and not any(raw[i] > 0 for i in range(1, len(raw), SLOT_WIDTH)):
        raise ValueError(f"Missing talents for flagged form: {form.get('name', '')}")
    if not raw:
        return
    # Old clients ignore the optional extension and still decode exactly 113 values.
    form['talentData'] = raw[:LEGACY_LENGTH] + [0] * max(0, LEGACY_LENGTH - len(raw))
    if len(raw) > LEGACY_LENGTH:
        form['additionalTalentData'] = raw[LEGACY_LENGTH:]
