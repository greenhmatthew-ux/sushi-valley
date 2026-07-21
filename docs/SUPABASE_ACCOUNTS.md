# Supabase Accounts, Characters, and Admin

Sushi Valley can run in two modes:

- **Local mode:** the existing browser save remains available with no Supabase configuration.
- **Account mode:** Supabase Auth owns the session, Japanese learning is shared across the account,
  and each account can have up to three independent RPG characters.

The preserved Kana Sprint `public.profiles.progress` data is not read, changed, or migrated by this
system. Reboot data lives in its own `game_learning_profiles` and `game_characters` tables.

## Data ownership

Account-wide data:

- sparse SRS scheduling and unlock state;
- total reviews and correct answers;
- read learning-content IDs.

Per-character data:

- RPG XP, build, inventory, chest, gear, coins, quests, professions, social state, resources,
  farming, Raids, Expeditions, events, and notifications;
- current map, position, facing, HP damage, day, and season.

Static Japanese prompts, answers, meanings, and source metadata remain in the shipped data bundle.
They are rehydrated locally and are deliberately not duplicated into every cloud save.

## 1. Configure the Supabase project

Apply [`supabase/migrations/202607170001_game_accounts_characters.sql`](../supabase/migrations/202607170001_game_accounts_characters.sql)
to the same Supabase project used for authentication. Either paste it into the Supabase SQL editor or
initialize/link the Supabase CLI for this checkout and push the migration:

```powershell
supabase init
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

The migration enables and forces Row Level Security, allows players to read only their own rows,
and revokes direct browser writes. Character creation, saving, deletion, and admin changes go through
revision-checked database functions.

In Supabase Auth, enable email/password sign-in. Decide whether email confirmation is required before
testing sign-up; the startup screen handles both immediate sessions and confirmation-required sign-ups.

## 2. Add browser-safe environment values

Copy `.env.example` to `.env.local` and fill in the project URL and public publishable key:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

The older public anon key also works under `VITE_SUPABASE_ANON_KEY`. Never add a Supabase service-role
key to a `VITE_` variable, Cloudflare Pages client environment, or repository file. The browser does
not need one.

Restart Vite after changing environment variables:

```powershell
npm.cmd run game:dev -- --host 127.0.0.1
```

With valid values, the account and three-slot character screen appears before Phaser boots. With no
values, the existing local game boots normally.

## 3. Create the first admin

1. Sign up through the Sushi Valley account screen and complete email confirmation if enabled.
2. In the Supabase SQL editor, run this with the real account email:

```sql
select public.promote_game_admin('owner@example.com');
```

3. Sign out and back in, then open **Admin** from the character screen.

`promote_game_admin` is unavailable to anonymous and authenticated browser roles. It is intentionally
reserved for the SQL editor/service role, so a user cannot promote themselves from DevTools.

An admin can select any character and replace its name, XP/level-equivalent progression, coins,
inventory, equipment, build, full character document, world document, and account learning document.
Every change requires a reason, checks the revisions the admin loaded, and writes an audit record.
Stale player or admin saves fail instead of silently overwriting a newer edit.

Character selection is tab-scoped, so separate tabs can safely select different slots. Do not actively
play the same character in two tabs at once: both tabs share that character's local cache, and the
optimistic revision check will intentionally reject one of the competing cloud writers.

## Manual test

1. Start without `.env.local`; confirm the local save still boots and reloads.
2. Add the public Supabase values, sign up, and create Character A by importing the local save.
3. Create Character B as new. Give A RPG XP or an item, switch to B by reloading into Characters,
   and confirm B did not receive it.
4. Review a Japanese card on A, switch to B, and confirm its schedule/review total is shared while B's
   RPG XP remains independent.
5. Reset B and confirm A, the account session, and account learning remain.
6. Promote the admin account, edit a character through Admin, reload that character, and confirm the
   server value wins. Leave the admin editor open in a second window and verify its stale save is
   rejected after another change.
7. Confirm a normal account cannot see the Admin button or call the admin database function.

## Security boundary

RLS and the database functions protect one account from another and make admin authority server-owned.
The single-player game still computes rewards and progression in the browser, so this is not an
anti-cheat or server-authoritative economy. Moving combat, drops, crafting, and rewards to trusted
server transactions would be a separate architecture project.
