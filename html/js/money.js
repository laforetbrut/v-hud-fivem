/*
    js/money.js

    The money readout and the toast stack. Two unrelated things that share this file because
    both are "something appears, then goes away again", and both need the same timer discipline
    to avoid leaking one per event.
*/

const Money = (() => {

    let cashTimer = null;
    let bankTimer = null;
    let deltaTimer = null;
    let format = { symbol: '$', symbolPosition: 'prefix', thousands: ' ' };

    /** Format an amount the way the server configured. */
    function amount(value) {
        const number = U.money(value, format.thousands);
        return format.symbolPosition === 'suffix'
            ? `${number}${format.symbol}`
            : `${format.symbol}${number}`;
    }

    function configure(money) {
        if (money) format = Object.assign(format, money);
    }

    let revealTimer = null;

    /**
     * Show the money element even when the player has it switched off.
     *
     * The element ships OFF, because a cash and bank readout parked in the corner all session
     * is the most immersion-breaking thing a HUD does. But `/cash` is a direct question and it
     * deserves a direct answer, so the element is revealed for the length of the readout and
     * then goes back to whatever the settings say.
     */
    function reveal(duration) {
        if (format.showOnCommand === false) return;

        const host = U.el('el-money');
        if (!host) return;

        U.attr(host, 'data-visible', true);
        clearTimeout(revealTimer);
        revealTimer = setTimeout(() => {
            const on = !!(S.settings && S.settings.show && S.settings.show.money);
            U.attr(host, 'data-visible', on);
        }, (duration || 5000) + 400);
    }

    /** Show one account's balance for `duration`, then hide it again. */
    function showAccount(account, value, duration) {
        const row = U.el(`money-${account}`);
        const label = U.el(`money-${account}-value`);
        if (!row || !label) return;

        U.text(label, amount(value));
        U.attr(row, 'data-on', true);

        const timer = account === 'cash' ? cashTimer : bankTimer;
        clearTimeout(timer);

        const next = setTimeout(() => {
            // The bank row can be pinned on permanently by the server; the cash row never is.
            const pinned = account === 'bank' && format.alwaysShowBank === true;
            if (!pinned) U.attr(row, 'data-on', false);
        }, duration || 5000);

        if (account === 'cash') cashTimer = next; else bankTimer = next;
    }

    /** The +/- banner on a money change, plus the balance it left behind. */
    function change(data) {
        const delta = U.el('money-delta');
        if (!delta) return;

        const sign = data.minus ? 'minus' : 'plus';
        U.text(delta, `${data.minus ? '-' : '+'}${amount(data.amount)}`);
        U.attr(delta, 'data-sign', sign);
        U.attr(delta, 'data-on', true);

        showAccount(data.account, data.account === 'bank' ? data.bank : data.cash, data.duration);

        clearTimeout(deltaTimer);
        deltaTimer = setTimeout(() => U.attr(delta, 'data-on', false), data.duration || 3500);
    }

    /** Keep the pinned bank row current without flashing the banner. */
    function setAlwaysBank(on, value) {
        const row = U.el('money-bank');
        if (!row) return;

        if (on) {
            U.text(U.el('money-bank-value'), amount(value || 0));
            U.attr(row, 'data-on', true);
        }
    }

    return { configure, showAccount, change, setAlwaysBank, amount, reveal };

})();


/*
    Toasts.

    Worth being precise about what these are, because it is the most common misunderstanding
    about a QBCore HUD: on a stock server the notifications belong to qb-core, not here.
    `QBCore.Functions.Notify` posts to qb-core's own NUI page. These toasts are only for what
    this resource raises itself, plus anything that calls its Notify export - which is why
    they are themed and qb-core's are not.
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
