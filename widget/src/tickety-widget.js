/**
 * Tickety Embeddable Checkout Widget v1.0.0
 *
 * Usage:
 *   <script src="https://hnouslchigcmbiovdbfz.supabase.co/storage/v1/object/public/widget/v1/tickety-widget.js"></script>
 *   <script>
 *     Tickety.init({
 *       key: 'twk_live_xxxx',
 *       eventId: 'uuid',
 *       container: '#tickety-button',
 *       onComplete: (data) => console.log('Done', data),
 *       onClose: () => console.log('Closed'),
 *     });
 *   </script>
 */
(function() {
  'use strict';

  var VERSION = '1.0.0';
  var API_BASE = 'https://hnouslchigcmbiovdbfz.supabase.co/functions/v1';
  var CHECKOUT_FN = API_BASE + '/widget-checkout-page';

  var _config = null;
  var _overlay = null;
  var _iframe = null;
  var _messageHandler = null;

  var Tickety = {
    version: VERSION,

    init: function(config) {
      if (!config.key) throw new Error('Tickety: key required');
      if (!config.eventId) throw new Error('Tickety: eventId required');

      _config = {
        key: config.key,
        eventId: config.eventId,
        container: config.container || null,
        theme: config.theme || {},
        onComplete: config.onComplete || null,
        onClose: config.onClose || null,
        onError: config.onError || null,
        buttonText: config.buttonText || 'Get Tickets',
      };

      if (_config.container) {
        var el = typeof _config.container === 'string'
          ? document.querySelector(_config.container) : _config.container;
        if (el) _renderButton(el);
      }

      _setupMessageListener();
      return Tickety;
    },

    checkout: function() {
      if (!_config) throw new Error('Tickety: call init() first');
      _openCheckout();
    },

    close: function() { _closeCheckout(); },

    destroy: function() {
      _closeCheckout();
      if (_messageHandler) {
        window.removeEventListener('message', _messageHandler);
        _messageHandler = null;
      }
      _config = null;
    },
  };

  function _renderButton(container) {
    var primary = _config.theme.primaryColor || '#6366F1';
    var btn = document.createElement('button');
    btn.className = 'tickety-btn';
    btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle;margin-right:6px"><path d="M2 9a3 3 0 0 1 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 1 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2Z"/><path d="M13 5v2"/><path d="M13 17v2"/><path d="M13 11v2"/></svg>' + _config.buttonText;
    btn.style.cssText = 'display:inline-flex;align-items:center;justify-content:center;padding:12px 24px;background:' + primary + ';color:#fff;border:none;border-radius:8px;font-family:Inter,-apple-system,BlinkMacSystemFont,sans-serif;font-size:16px;font-weight:600;cursor:pointer;transition:opacity 0.2s;';
    btn.onmouseenter = function() { btn.style.opacity = '0.9'; };
    btn.onmouseleave = function() { btn.style.opacity = '1'; };
    btn.onclick = function() { Tickety.checkout(); };
    container.innerHTML = '';
    container.appendChild(btn);
  }

  function _openCheckout() {
    if (_overlay) return;

    // Fetch checkout HTML from edge function, inject via srcdoc
    var params = '?key=' + encodeURIComponent(_config.key)
      + '&event=' + encodeURIComponent(_config.eventId);
    if (_config.theme.primaryColor) {
      params += '&color=' + encodeURIComponent(_config.theme.primaryColor.replace('#', ''));
    }

    fetch(CHECKOUT_FN + params)
      .then(function(res) { return res.text(); })
      .then(function(html) {
        _overlay = document.createElement('div');
        _overlay.id = 'tickety-overlay';
        _overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,0.6);backdrop-filter:blur(4px);display:flex;align-items:center;justify-content:center;opacity:0;transition:opacity 0.25s ease;';
        _overlay.addEventListener('click', function(e) {
          if (e.target === _overlay) _closeCheckout();
        });

        var box = document.createElement('div');
        box.style.cssText = 'width:100%;max-width:480px;height:90vh;max-height:700px;border-radius:16px;overflow:hidden;box-shadow:0 25px 50px -12px rgba(0,0,0,0.4);transform:translateY(20px);transition:transform 0.3s ease;background:#fff;';

        _iframe = document.createElement('iframe');
        _iframe.style.cssText = 'width:100%;height:100%;border:none;background:#fff;';
        _iframe.srcdoc = html;
        _iframe.setAttribute('sandbox', 'allow-scripts allow-forms allow-same-origin allow-popups allow-popups-to-escape-sandbox');
        _iframe.setAttribute('allow', 'payment');

        box.appendChild(_iframe);
        _overlay.appendChild(box);
        document.body.appendChild(_overlay);
        document.body.style.overflow = 'hidden';

        requestAnimationFrame(function() {
          _overlay.style.opacity = '1';
          box.style.transform = 'translateY(0)';
        });

        document.addEventListener('keydown', _handleEscape);
      })
      .catch(function(err) {
        if (_config.onError) _config.onError({ message: err.message });
      });
  }

  function _closeCheckout() {
    if (!_overlay) return;
    _overlay.style.opacity = '0';
    setTimeout(function() {
      if (_overlay && _overlay.parentNode) _overlay.parentNode.removeChild(_overlay);
      _overlay = null;
      _iframe = null;
      document.body.style.overflow = '';
    }, 250);
    document.removeEventListener('keydown', _handleEscape);
    if (_config && _config.onClose) _config.onClose();
  }

  function _handleEscape(e) {
    if (e.key === 'Escape') _closeCheckout();
  }

  function _setupMessageListener() {
    if (_messageHandler) window.removeEventListener('message', _messageHandler);
    _messageHandler = function(event) {
      if (!event.data || typeof event.data !== 'object') return;
      if (!event.data.type || event.data.type.indexOf('tickety:') !== 0) return;
      switch (event.data.type) {
        case 'tickety:checkout_complete':
          if (_config && _config.onComplete) _config.onComplete(event.data.payload);
          _closeCheckout();
          break;
        case 'tickety:close':
          _closeCheckout();
          break;
      }
    };
    window.addEventListener('message', _messageHandler);
  }

  if (typeof window !== 'undefined') window.Tickety = Tickety;
})();
