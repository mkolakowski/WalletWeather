"""Deleting a user: your own (DELETE /api/me, GET /api/me/deletion-check)
and, as an admin, someone else's (DELETE /api/admin/users/{uid}).

The rule (docs/dev/decisions/legal-risk.md): deletion is refused while the
user is the only owner of an account other people can see. An account with
another owner stays; an account nobody else can see goes with the user.

Not covered here: a Google-only user, who confirms by typing their email
address. The tests have no way to sign one in (it needs Google), so that
branch is untested; the gap is recorded on issue #48.
"""
from datetime import date

import pytest
from fastapi.testclient import TestClient

from conftest import share_account, unique_email

PASSWORD = "correct-horse-battery"


def register(app):
    """A new signed-in user with their own client (their own cookies)."""
    c = TestClient(app)
    email = unique_email()
    r = c.post("/api/auth/register", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, {"email": email, "id": r.json()["id"]}


def make_account(c, name="Checking"):
    r = c.post("/api/accounts", json={
        "name": name, "starting_balance": 100.0,
        "starting_date": date.today().isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def share(c, account_id, other, level):
    # The way the app does it: an invitation the other person accepts.
    # Taking access away again is the owner's alone.
    if level == "deny":
        r = c.post("/api/permissions", json={
            "account_id": account_id, "user_id": other["id"], "level": "deny"})
        assert r.status_code == 200, r.text
        return
    share_account(c, account_id, level, email=other["email"], password=PASSWORD)


def delete_me(c, password=PASSWORD):
    return c.request("DELETE", "/api/me", json={"password": password})


def account_ids(c):
    return [a["id"] for a in c.get("/api/accounts").json()]


@pytest.fixture
def two_users(app_started):
    a, a_info = register(app_started)
    b, b_info = register(app_started)
    return a, a_info, b, b_info


def test_deletion_check_for_a_user_with_an_unshared_account(client, registered):
    account_id = make_account(client)
    r = client.get("/api/me/deletion-check")
    assert r.status_code == 200
    assert r.json() == {
        "can_delete": True,
        "accounts_deleted": [{"id": account_id, "name": "Checking"}],
        "accounts_kept": [],
        "blocking_accounts": [],
        "has_password": True,
        "is_demo": False,
    }


def test_deleting_removes_the_user_and_ends_the_session(client, registered):
    make_account(client)
    r = delete_me(client)
    assert r.status_code == 200, r.text
    assert r.json() == {"ok": True}
    # The session is over, and the sign-in no longer works.
    assert client.get("/api/me").status_code == 401
    r = client.post("/api/auth/login",
                    json={"email": registered["email"], "password": PASSWORD})
    assert r.status_code == 401
    # The email address is free again.
    r = client.post("/api/auth/register",
                    json={"email": registered["email"], "password": PASSWORD})
    assert r.status_code == 200
    assert account_ids(client) == []


def test_a_wrong_password_deletes_nothing(client, registered):
    r = delete_me(client, password="not-the-password")
    assert r.status_code == 403
    assert client.get("/api/me").status_code == 200


def test_no_confirmation_deletes_nothing(client, registered):
    r = client.request("DELETE", "/api/me", json={})
    assert r.status_code == 403
    assert client.get("/api/me").status_code == 200


def test_deleting_needs_a_session(client):
    assert delete_me(client).status_code == 401
    assert client.get("/api/me/deletion-check").status_code == 401


def test_refused_while_the_only_owner_of_a_shared_account(two_users):
    a, a_info, b, b_info = two_users
    account_id = make_account(a, "Joint")
    share(a, account_id, b_info, "read")

    check = a.get("/api/me/deletion-check").json()
    assert check["can_delete"] is False
    assert check["blocking_accounts"] == [{
        "id": account_id, "name": "Joint",
        "shared_with": [{"email": b_info["email"], "level": "read"}]}]

    r = delete_me(a)
    assert r.status_code == 409
    detail = r.json()["detail"]
    assert detail["blocking_accounts"][0]["id"] == account_id
    assert "message" in detail
    # Nothing was deleted: both people still have the account.
    assert a.get("/api/me").status_code == 200
    assert account_id in account_ids(a)
    assert account_id in account_ids(b)


def test_an_account_with_another_owner_stays(two_users):
    a, a_info, b, b_info = two_users
    account_id = make_account(a, "Joint")
    private_id = make_account(a, "Mine alone")
    share(a, account_id, b_info, "owner")

    check = a.get("/api/me/deletion-check").json()
    assert check["can_delete"] is True
    assert check["accounts_kept"] == [
        {"id": account_id, "name": "Joint", "new_owner_email": b_info["email"]}]
    assert check["accounts_deleted"] == [{"id": private_id, "name": "Mine alone"}]

    assert delete_me(a).status_code == 200
    # The other owner keeps the account and can still use it.
    assert account_ids(b) == [account_id]
    r = b.post(f"/api/accounts/{account_id}/transactions", json={
        "description": "after the handover", "amount": -1.0,
        "forecast_date": date.today().isoformat(), "is_actual": False})
    assert r.status_code == 200, r.text
    assert b.get(f"/api/accounts/{account_id}/forecast").status_code == 200


def test_removing_the_sharing_unblocks_deletion(two_users):
    a, a_info, b, b_info = two_users
    account_id = make_account(a, "Joint")
    share(a, account_id, b_info, "edit")
    assert delete_me(a).status_code == 409
    share(a, account_id, b_info, "deny")
    assert delete_me(a).status_code == 200
    assert account_ids(b) == []


def test_having_access_to_someone_elses_account_doesnt_block(two_users):
    a, a_info, b, b_info = two_users
    account_id = make_account(b, "B's")
    share(b, account_id, a_info, "edit")
    assert a.get("/api/me/deletion-check").json()["can_delete"] is True
    assert delete_me(a).status_code == 200
    assert account_ids(b) == [account_id]


def test_a_transfer_between_accounts_that_stay_survives(two_users):
    a, a_info, b, b_info = two_users
    joint = make_account(a, "Joint")
    share(a, joint, b_info, "owner")
    bs = make_account(b, "B's")
    share(b, bs, a_info, "edit")
    r = a.post("/api/transfers", json={
        "from_account_id": joint, "to_account_id": bs, "amount": 25.0,
        "transfer_date": date.today().isoformat()})
    assert r.status_code == 200, r.text

    assert delete_me(a).status_code == 200
    # Both accounts stayed, so the transfer the deleted user made does too.
    assert sorted(account_ids(b)) == sorted([joint, bs])
    transfers = b.get("/api/transfers").json()
    assert len([t for t in transfers["transfers"]
                if {t["from_account_id"], t["to_account_id"]} == {joint, bs}]) == 1


# ---------- An admin deleting someone else (#57) ----------

@pytest.fixture
def admin(app_started):
    """A signed-in admin. Admins are named in ADMIN_EMAILS, read at start-up,
    so the test adds its own address to that set and takes it out again."""
    from app import main
    c, info = register(app_started)
    main.ADMIN_EMAILS.add(info["email"])
    yield c
    main.ADMIN_EMAILS.discard(info["email"])


def admin_delete(admin_client, who):
    users = admin_client.get("/api/admin/users").json()
    users = users["users"] if isinstance(users, dict) else users
    uid = next(u["id"] for u in users if u["email"] == who["email"])
    return admin_client.delete(f"/api/admin/users/{uid}")


def test_admin_delete_is_refused_for_the_only_owner_of_a_shared_account(admin, two_users):
    a, a_info, b, b_info = two_users
    account_id = make_account(a, "Joint")
    share(a, account_id, b_info, "edit")

    r = admin_delete(admin, a_info)
    assert r.status_code == 409
    detail = r.json()["detail"]
    assert a_info["email"] in detail["message"]
    assert detail["blocking_accounts"] == [{
        "id": account_id, "name": "Joint",
        "shared_with": [{"email": b_info["email"], "level": "edit"}]}]
    assert a.get("/api/me").status_code == 200
    assert account_id in account_ids(b)


def test_admin_delete_keeps_an_account_with_another_owner(admin, two_users):
    a, a_info, b, b_info = two_users
    account_id = make_account(a, "Joint")
    make_account(a, "Mine alone")
    share(a, account_id, b_info, "owner")

    r = admin_delete(admin, a_info)
    assert r.status_code == 200, r.text
    assert r.json() == {"ok": True}
    assert a.get("/api/me").status_code == 401
    assert account_ids(b) == [account_id]


def test_admin_delete_needs_an_admin(two_users):
    a, a_info, b, b_info = two_users
    assert a.delete(f"/api/admin/users/{b_info['id']}").status_code == 403
    assert b.get("/api/me").status_code == 200
