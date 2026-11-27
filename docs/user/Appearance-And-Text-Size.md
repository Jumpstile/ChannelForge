# Appearance and Text Size

You can make ChannelForge easier to read. You can make the text bigger. You can pick a dark or light look.

## Change the text size

1. Open ChannelForge in your browser.
2. Look at the bar at the top of the page.
3. Find the box called **Text size**.
4. Pick one:
   - **Normal** (100%)
   - **Large** (125%)
   - **Extra large** (150%)

The change happens right away.

## The focus outline

The focus outline is the colored box that shows which button or field is selected when you use the keyboard or a remote.

There is no separate control for it. It gets thicker when you make the text bigger:

| Text size   | Outline thickness |
| ----------- | ----------------- |
| Normal      | 3 pixels          |
| Large       | 4 pixels          |
| Extra large | 5 pixels          |

## Switch dark or light

ChannelForge has this control. It is in the same top bar. Find the box called **Appearance**. Pick one:

- **Light**
- **Dark**
- **System** - follows your computer or phone. If your device switches to dark at night, ChannelForge switches too.

If you never pick, ChannelForge uses **System**.

## Where your choices are saved

**Appearance** (Light, Dark or System) is saved by ChannelForge itself, on the computer where ChannelForge runs. It is the same for everyone who opens that ChannelForge. If you open it in a different browser or on a different device, you see the same look.

Your browser also keeps a copy. The copy only helps the page open in the right look without a flash of the wrong one. If the two ever differ, ChannelForge's saved choice wins.

- The first time, if ChannelForge has nothing saved yet, your browser sends the choice it already has, one time.
- If ChannelForge cannot be reached, the page still opens and uses the copy in your browser, or **System**.
- If ChannelForge cannot save your choice, it tells you in plain words. The choice still works in this browser until you close the page. Press **Details** for the technical text.
- ChannelForge never deletes a saved-settings file it cannot read. It uses **System** and keeps the unreadable file next to the new one.

Changing the look does not change your lineups or guides.

**Text size** is still saved in this browser only. A different browser or computer starts at **Normal**.

- If you clear your browser's saved site data, your text size is lost.
- If your browser blocks saving, your text size still works until you close the page.

If nothing is saved anywhere, the text size is **Normal** and the appearance is **System**.

When sign-in is on, each person can also have their own look. ChannelForge keeps it in a separate file, `user-settings.json`, next to `users.json`, so a settings problem can never touch your passwords. A person's own choice wins. If they have none, the shared choice above is used, and if there is none either, **System**. Every role (Viewer, Editor and Admin) can change only its own look. Only an Admin can change the shared one. If `user-settings.json` cannot be read, ChannelForge uses the shared look. The unreadable file is moved aside, never deleted, the next time a look is saved. Deleting a user removes that user's saved look. The page itself does not show this choice yet; it is available through `GET` and `PUT /api/settings/me`.

Check [Current Limitations](CURRENT_LIMITATIONS.md) for what works today.
