"""Date format and row height: two per-person display settings (#286).

Stored like chart_position: PATCH /api/me/preferences sets them, GET /api/me
reads them back, null means unset (the web client then shows short dates and
roomy rows).
"""


def test_both_start_unset(client, registered):
    me = client.get("/api/me").json()
    assert me["date_format"] is None
    assert me["row_height"] is None


def test_set_both_and_read_them_back(client, registered):
    r = client.patch("/api/me/preferences",
                     json={"date_format": "iso", "row_height": "compact"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is True
    assert body["date_format"] == "iso"
    assert body["row_height"] == "compact"
    me = client.get("/api/me").json()
    assert me["date_format"] == "iso"
    assert me["row_height"] == "compact"
    # And back again: the other two allowed values.
    r = client.patch("/api/me/preferences",
                     json={"date_format": "short", "row_height": "roomy"})
    assert r.status_code == 200, r.text
    me = client.get("/api/me").json()
    assert (me["date_format"], me["row_height"]) == ("short", "roomy")


def test_one_setting_leaves_the_other_alone(client, registered):
    client.patch("/api/me/preferences", json={"row_height": "compact"})
    r = client.patch("/api/me/preferences", json={"date_format": "iso"})
    assert r.status_code == 200, r.text
    me = client.get("/api/me").json()
    assert me["date_format"] == "iso"
    assert me["row_height"] == "compact"


def test_other_preferences_are_untouched(client, registered):
    client.patch("/api/me/preferences",
                 json={"theme_preference": "nord", "chart_position": "below"})
    client.patch("/api/me/preferences", json={"date_format": "iso"})
    me = client.get("/api/me").json()
    assert me["theme_preference"] == "nord"
    assert me["chart_position"] == "below"


def test_an_unknown_date_format_is_refused(client, registered):
    client.patch("/api/me/preferences", json={"date_format": "iso"})
    for bad in ("long", "ISO", "", "2026-11-12"):
        r = client.patch("/api/me/preferences", json={"date_format": bad})
        assert r.status_code == 400, (bad, r.text)
        assert "date_format" in r.json()["detail"]
    assert client.get("/api/me").json()["date_format"] == "iso"


def test_an_unknown_row_height_is_refused(client, registered):
    client.patch("/api/me/preferences", json={"row_height": "compact"})
    for bad in ("tall", "Compact", "", "34"):
        r = client.patch("/api/me/preferences", json={"row_height": bad})
        assert r.status_code == 400, (bad, r.text)
        assert "row_height" in r.json()["detail"]
    assert client.get("/api/me").json()["row_height"] == "compact"


def test_a_refused_value_changes_nothing_else_in_the_request(client, registered):
    r = client.patch("/api/me/preferences",
                     json={"date_format": "iso", "row_height": "nope"})
    assert r.status_code == 400
    # The request fails whole: the good date format isn't kept.
    assert client.get("/api/me").json()["date_format"] is None


def test_each_person_has_their_own(client, registered, app_started):
    from conftest import register
    client.patch("/api/me/preferences", json={"date_format": "iso"})
    other, _ = register(app_started)
    assert other.get("/api/me").json()["date_format"] is None


def test_signed_out_is_refused(client):
    r = client.patch("/api/me/preferences", json={"date_format": "iso"})
    assert r.status_code == 401
