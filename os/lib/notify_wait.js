const { Gio, GLib } = imports.gi;

const [specPath, timeoutArg] = ARGV;
const [, bytes] = GLib.file_get_contents(specPath);
const message = JSON.parse(new TextDecoder().decode(bytes)).message;
const urgency = { low: 0, normal: 1, critical: 2 }[message.urgency] ?? 1;
const actions = [];
for (const action of message.actions || []) actions.push(String(action.id), String(action.label));

const bus = Gio.DBus.session;
const loop = new GLib.MainLoop(null, false);
let notificationId = -1;
let chosen = '';

bus.signal_subscribe(null, 'org.freedesktop.Notifications', null, '/org/freedesktop/Notifications', null, Gio.DBusSignalFlags.NONE,
    (_conn, _sender, _path, _iface, signal, params) => {
        const values = params.deep_unpack();
        if (values[0] !== notificationId) return;
        if (signal === 'ActionInvoked') chosen = values[1];
        if (signal === 'ActionInvoked' || signal === 'NotificationClosed') loop.quit();
    });

const hints = { urgency: new GLib.Variant('y', urgency) };
const reply = bus.call_sync('org.freedesktop.Notifications', '/org/freedesktop/Notifications', 'org.freedesktop.Notifications', 'Notify',
    new GLib.Variant('(susssasa{sv}i)', [String(message.source), 0, String(message.icon || ''), String(message.title), String(message.body || ''), actions, hints, message.expire_ms ?? -1]),
    null, Gio.DBusCallFlags.NONE, 10000, null);
notificationId = reply.deep_unpack()[0];

GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, Math.max(1, parseInt(timeoutArg || '86400', 10)), () => { loop.quit(); return GLib.SOURCE_REMOVE; });
loop.run();
print(chosen);
