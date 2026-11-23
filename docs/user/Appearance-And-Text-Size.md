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

## Where your choice is saved today

Your choices are saved in this browser only. They are not saved in ChannelForge itself.

- If you open ChannelForge in a different browser, it starts fresh.
- If you use a different computer, it starts fresh.
- If you clear your browser's saved site data, your choices are lost.
- If your browser blocks saving, your choice still works until you close the page.

When you start fresh, the text size is **Normal** and the appearance is **System**.

## Planned: saving on the server

**This is planned. It is not available yet.**

The plan is for ChannelForge to be a client and server program. The server is the part that runs the engine. Your browser is the client.

The decision is to save appearance on the server. Then your choice would follow you to a new browser or computer. Today, it is saved in the browser only.

The plan says what would happen when the server version exists:

- Your browser would ask the server for your appearance.
- If the server has nothing saved yet, your browser would send the choice it already has, one time.
- If the server and the browser disagree, the server wins.
- If the server cannot be reached, the page would still open and use the choice saved in the browser.

Still undecided: whether the server setting is shared by everyone or kept for each person. The current suggestion is shared first.

The plan notes only name appearance (light, dark, system) for the server. They do not say text size will move there.

Plans can change. Check [Current Limitations](CURRENT_LIMITATIONS.md) for what works today.
