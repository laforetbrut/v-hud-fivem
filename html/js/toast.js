/*
    js/toast.js

    The toast stack.

    Worth being precise about what these are, because it is the most common misunderstanding
    about a QBCore HUD: on a stock server the notifications belong to qb-core, not here.
    `QBCore.Functions.Notify` posts to qb-core's own NUI page. These toasts are only for what
    this resource raises itself, plus anything that calls its Notify export - which is why
    they are themed and qb-core's are not.

    `/cash` and `/bank` answer through here too. There is no money element: a balance parked
    on screen all session is the thing every player turns off first, so it is not built. A
    balance appears because it was asked for, and then it goes away like any other message.
*/

const Toast = (() => {

    let container = null;
    let options = { position: 'top-center', duration: 4000, maxVisible: 4 };
    const live = [];

    const POSITIONS = {
        'top-center':    { top: '6%',    left: '50%', transform: 'translateX(-50%)', align: 'center' },
        'top-right':     { top: '6%',    right: '2%', transform: 'none',             align: 'flex-end' },
        'top-left':      { top: '6%',    left: '2%',  transform: 'none',             align: 'flex-start' },
        'bottom-center': { bottom: '12%', left: '50%', transform: 'translateX(-50%)', align: 'center' },
        'bottom-right':  { bottom: '12%', right: '2%', transform: 'none',            align: 'flex-end' },
    };

    function configure(config) {
        if (config) options = Object.assign(options, config);

        container = container || U.el('toasts');
        if (!container) return;

        const place = POSITIONS[options.position] || POSITIONS['top-center'];
        container.style.cssText = '';
        container.style.top = place.top || 'auto';
        container.style.bottom = place.bottom || 'auto';
        container.style.left = place.left || 'auto';
        container.style.right = place.right || 'auto';
        container.style.transform = place.transform;
        container.style.alignItems = place.align;
    }

    /** Drop the oldest until at most `maxVisible` remain. A HUD is not a message log: a queue
     *  means being told about something that happened four minutes ago. */
    function trim() {
        while (live.length > options.maxVisible) {
            const oldest = live.shift();
            clearTimeout(oldest.timer);
            remove(oldest.node);
        }
    }

    function remove(node) {
        if (!node || !node.parentNode) return;
        U.attr(node, 'data-out', true);
        setTimeout(() => node.remove(), 250);
    }

    function show(message, kind, duration) {
        container = container || U.el('toasts');
        if (!container || !message) return;

        const node = U.make('div', { class: 'toast', 'data-kind': kind || 'primary', text: message });
        container.appendChild(node);

        const entry = { node, timer: null };
        entry.timer = setTimeout(() => {
            const index = live.indexOf(entry);
            if (index >= 0) live.splice(index, 1);
            remove(node);
        }, duration || options.duration);

        live.push(entry);
        trim();
    }

    return { configure, show };

})();
