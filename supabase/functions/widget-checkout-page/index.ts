import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

// Serve the checkout HTML page with correct Content-Type.
// This edge function exists because Supabase Storage serves files
// as text/plain regardless of upload content-type headers.

serve(async (req) => {
  // Pass through query params (key, event, color, v)
  const url = new URL(req.url)
  const key = url.searchParams.get('key') || ''
  const event = url.searchParams.get('event') || ''
  const color = url.searchParams.get('color') || ''
  const v = url.searchParams.get('v') || '1.0.0'

  const html = CHECKOUT_HTML
    .replace('__WIDGET_KEY__', escapeAttr(key))
    .replace('__EVENT_ID__', escapeAttr(event))
    .replace('__CUSTOM_COLOR__', escapeAttr(color))
    .replace('__VERSION__', escapeAttr(v))

  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'public, max-age=300',
    },
  })
})

function escapeAttr(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

const CHECKOUT_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tickety Checkout</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <script src="https://js.stripe.com/v3/"></script>
  <style>
    :root {
      --primary: #6366F1;
      --primary-hover: #5558E3;
      --bg: #FFFFFF;
      --bg-secondary: #F9FAFB;
      --text: #111827;
      --text-secondary: #6B7280;
      --border: #E5E7EB;
      --success: #10B981;
      --error: #EF4444;
      --radius: 12px;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: var(--bg); color: var(--text); line-height: 1.5;
      -webkit-font-smoothing: antialiased;
    }
    .checkout-container { display: flex; flex-direction: column; height: 100vh; overflow-y: auto; }
    .header {
      display: flex; align-items: center; justify-content: space-between;
      padding: 16px 20px; border-bottom: 1px solid var(--border);
      position: sticky; top: 0; background: var(--bg); z-index: 10;
    }
    .header h1 { font-size: 16px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; margin-right: 12px; }
    .close-btn {
      width: 32px; height: 32px; border-radius: 50%; border: none;
      background: var(--bg-secondary); cursor: pointer; display: flex;
      align-items: center; justify-content: center; flex-shrink: 0;
    }
    .close-btn:hover { background: var(--border); }
    .close-btn svg { width: 16px; height: 16px; stroke: var(--text-secondary); }
    .step-indicator { display: flex; gap: 4px; padding: 12px 20px; background: var(--bg-secondary); }
    .step-dot { flex: 1; height: 3px; border-radius: 2px; background: var(--border); transition: background 0.3s; }
    .step-dot.active { background: var(--primary); }
    .step-dot.done { background: var(--success); }
    .step-content { flex: 1; padding: 20px; display: none; }
    .step-content.active { display: block; }
    .section-title { font-size: 14px; font-weight: 600; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 12px; }
    .event-info { display: flex; gap: 12px; padding: 12px; background: var(--bg-secondary); border-radius: var(--radius); margin-bottom: 20px; }
    .event-image { width: 64px; height: 64px; border-radius: 8px; object-fit: cover; background: var(--border); }
    .event-details { flex: 1; min-width: 0; }
    .event-details h2 { font-size: 15px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .event-meta { font-size: 13px; color: var(--text-secondary); margin-top: 2px; }
    .ticket-type { display: flex; align-items: center; padding: 14px; border: 1px solid var(--border); border-radius: var(--radius); margin-bottom: 8px; transition: border-color 0.15s; }
    .ticket-type:hover { border-color: var(--primary); }
    .ticket-type.sold-out { opacity: 0.5; pointer-events: none; }
    .ticket-icon { font-size: 20px; margin-right: 12px; width: 28px; text-align: center; }
    .ticket-info { flex: 1; min-width: 0; }
    .ticket-name { font-size: 14px; font-weight: 600; }
    .ticket-desc { font-size: 12px; color: var(--text-secondary); margin-top: 1px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .ticket-price { font-size: 14px; font-weight: 600; color: var(--primary); margin-right: 12px; white-space: nowrap; }
    .qty-control { display: flex; align-items: center; gap: 8px; }
    .qty-btn { width: 30px; height: 30px; border-radius: 50%; border: 1px solid var(--border); background: var(--bg); cursor: pointer; display: flex; align-items: center; justify-content: center; font-size: 16px; font-weight: 500; transition: all 0.15s; }
    .qty-btn:hover { border-color: var(--primary); color: var(--primary); }
    .qty-btn:disabled { opacity: 0.3; pointer-events: none; }
    .qty-value { width: 24px; text-align: center; font-size: 15px; font-weight: 600; }
    .form-group { margin-bottom: 16px; }
    .form-label { display: block; font-size: 13px; font-weight: 500; margin-bottom: 6px; }
    .form-input { width: 100%; padding: 10px 14px; border: 1px solid var(--border); border-radius: 8px; font-family: inherit; font-size: 14px; color: var(--text); outline: none; transition: border-color 0.15s; }
    .form-input:focus { border-color: var(--primary); }
    .form-input::placeholder { color: #9CA3AF; }
    .promo-row { display: flex; gap: 8px; margin-top: 16px; }
    .promo-row .form-input { flex: 1; }
    .promo-btn { padding: 0 16px; border-radius: 8px; border: 1px solid var(--primary); background: transparent; color: var(--primary); font-weight: 600; font-size: 13px; cursor: pointer; white-space: nowrap; transition: all 0.15s; }
    .promo-btn:hover { background: var(--primary); color: #fff; }
    .promo-result { font-size: 13px; margin-top: 8px; padding: 8px 12px; border-radius: 8px; }
    .promo-result.success { background: #ECFDF5; color: #065F46; }
    .promo-result.error { background: #FEF2F2; color: #991B1B; }
    .summary-card { background: var(--bg-secondary); border-radius: var(--radius); padding: 16px; margin-bottom: 20px; }
    .summary-line { display: flex; justify-content: space-between; font-size: 14px; padding: 4px 0; }
    .summary-line.total { font-weight: 700; font-size: 16px; border-top: 1px solid var(--border); margin-top: 8px; padding-top: 10px; }
    .summary-line .label { color: var(--text-secondary); }
    .summary-line.total .label { color: var(--text); }
    #card-element { padding: 12px 14px; border: 1px solid var(--border); border-radius: 8px; transition: border-color 0.15s; }
    #card-element.StripeElement--focus { border-color: var(--primary); }
    #card-element.StripeElement--invalid { border-color: var(--error); }
    #card-errors { font-size: 13px; color: var(--error); margin-top: 8px; min-height: 20px; }
    .footer { padding: 16px 20px; border-top: 1px solid var(--border); background: var(--bg); position: sticky; bottom: 0; }
    .primary-btn { width: 100%; padding: 14px; border: none; border-radius: var(--radius); background: var(--primary); color: #fff; font-family: inherit; font-size: 15px; font-weight: 600; cursor: pointer; transition: background 0.15s, opacity 0.15s; }
    .primary-btn:hover { background: var(--primary-hover); }
    .primary-btn:disabled { opacity: 0.5; cursor: not-allowed; }
    .powered-by { text-align: center; margin-top: 10px; font-size: 11px; color: var(--text-secondary); }
    .powered-by a { color: var(--primary); text-decoration: none; }
    .success-view { display: none; flex-direction: column; align-items: center; justify-content: center; text-align: center; padding: 40px 20px; flex: 1; }
    .success-icon { width: 64px; height: 64px; border-radius: 50%; background: #ECFDF5; display: flex; align-items: center; justify-content: center; margin-bottom: 16px; }
    .success-icon svg { stroke: var(--success); width: 32px; height: 32px; }
    .success-title { font-size: 20px; font-weight: 700; margin-bottom: 8px; }
    .success-subtitle { font-size: 14px; color: var(--text-secondary); margin-bottom: 24px; }
    .loading { display: flex; align-items: center; justify-content: center; flex: 1; padding: 40px; }
    .spinner { width: 32px; height: 32px; border: 3px solid var(--border); border-top-color: var(--primary); border-radius: 50%; animation: spin 0.6s linear infinite; }
    @keyframes spin { to { transform: rotate(360deg); } }
    .error-view { display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; padding: 40px 20px; flex: 1; }
    .error-view p { color: var(--error); font-size: 14px; }
  </style>
</head>
<body>
  <div class="checkout-container" id="checkout">
    <div class="loading" id="loading-view"><div class="spinner"></div></div>
    <div class="error-view" id="error-view" style="display:none;">
      <p id="error-message">Something went wrong</p>
      <button class="primary-btn" style="margin-top:16px;max-width:200px;" onclick="location.reload()">Try Again</button>
    </div>
    <div id="main-flow" style="display:none;flex-direction:column;height:100vh;">
      <div class="header">
        <h1 id="event-title">Loading...</h1>
        <button class="close-btn" onclick="closeWidget()">
          <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </div>
      <div class="step-indicator">
        <div class="step-dot active" id="dot-0"></div>
        <div class="step-dot" id="dot-1"></div>
        <div class="step-dot" id="dot-2"></div>
      </div>
      <div class="step-content active" id="step-0">
        <div class="event-info" id="event-info"></div>
        <div class="section-title">Select Tickets</div>
        <div id="ticket-list"></div>
        <div class="promo-row">
          <input type="text" class="form-input" id="promo-input" placeholder="Promo code">
          <button class="promo-btn" id="promo-btn" onclick="applyPromo()">Apply</button>
        </div>
        <div id="promo-result"></div>
      </div>
      <div class="step-content" id="step-1">
        <div class="section-title">Your Details</div>
        <div class="form-group">
          <label class="form-label" for="buyer-email">Email *</label>
          <input type="email" class="form-input" id="buyer-email" placeholder="your@email.com" required>
        </div>
        <div class="form-group">
          <label class="form-label" for="buyer-name">Full Name</label>
          <input type="text" class="form-input" id="buyer-name" placeholder="John Doe">
        </div>
        <div class="summary-card" id="summary-step1"></div>
      </div>
      <div class="step-content" id="step-2">
        <div class="section-title">Payment</div>
        <div class="summary-card" id="summary-step2"></div>
        <div class="form-group">
          <label class="form-label">Card Details</label>
          <div id="card-element"></div>
          <div id="card-errors"></div>
        </div>
      </div>
      <div class="footer">
        <button class="primary-btn" id="action-btn" onclick="handleAction()">Continue</button>
        <div class="powered-by" id="powered-by">Secured by <a href="https://tickety.app" target="_blank">Tickety</a></div>
      </div>
    </div>
    <div class="success-view" id="success-view">
      <div class="success-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
      </div>
      <div class="success-title">You're all set!</div>
      <div class="success-subtitle" id="success-message">Check your email for your tickets.</div>
      <button class="primary-btn" style="max-width:200px;" onclick="closeWidget()">Done</button>
      <div class="powered-by" style="margin-top:16px;">Powered by <a href="https://tickety.app" target="_blank">Tickety</a></div>
    </div>
  </div>
  <script>
    const WIDGET_KEY = "__WIDGET_KEY__";
    const EVENT_ID = "__EVENT_ID__";
    const CUSTOM_COLOR = "__CUSTOM_COLOR__";
    const API_BASE = 'https://hnouslchigcmbiovdbfz.supabase.co/functions/v1';
    let currentStep = 0, eventData = null, ticketTypes = [], widgetConfig = {};
    let quantities = {}, promoDiscount = 0, promoCode = null;
    let stripeInstance = null, cardElement = null, checkoutSession = null, isProcessing = false;

    async function init() {
      if (!WIDGET_KEY || !EVENT_ID) { showError('Invalid widget configuration'); return; }
      try {
        const res = await fetch(API_BASE + '/widget-get-event', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ widget_key: WIDGET_KEY, event_id: EVENT_ID }),
        });
        if (!res.ok) { const err = await res.json(); throw new Error(err.error || 'Failed to load event'); }
        const data = await res.json();
        eventData = data.event; ticketTypes = data.ticket_types; widgetConfig = data.widget_config;
        applyTheme(); renderEvent(); renderTicketTypes();
        document.getElementById('loading-view').style.display = 'none';
        document.getElementById('main-flow').style.display = 'flex';
      } catch (err) { showError(err.message); }
    }

    function applyTheme() {
      const color = CUSTOM_COLOR ? '#' + CUSTOM_COLOR : widgetConfig.primary_color || '#6366F1';
      document.documentElement.style.setProperty('--primary', color);
      const hex = color.replace('#',''); const num = parseInt(hex,16);
      let r = Math.min(255,Math.max(0,(num>>16)-15));
      let g = Math.min(255,Math.max(0,((num>>8)&0xFF)-15));
      let b = Math.min(255,Math.max(0,(num&0xFF)-15));
      document.documentElement.style.setProperty('--primary-hover', '#'+(r<<16|g<<8|b).toString(16).padStart(6,'0'));
      if (widgetConfig.font_family) document.body.style.fontFamily = "'" + widgetConfig.font_family + "', sans-serif";
      if (widgetConfig.show_powered_by === false) document.getElementById('powered-by').style.display = 'none';
    }

    function renderEvent() {
      document.getElementById('event-title').textContent = eventData.title;
      const d = new Date(eventData.start_date);
      const ds = d.toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric',hour:'numeric',minute:'2-digit'});
      document.getElementById('event-info').innerHTML =
        (eventData.image_url ? '<img class="event-image" src="'+esc(eventData.image_url)+'" alt="'+esc(eventData.title)+'">' : '<div class="event-image"></div>') +
        '<div class="event-details"><h2>'+esc(eventData.title)+'</h2><div class="event-meta">'+esc(ds)+'</div><div class="event-meta">'+esc(eventData.location||'')+'</div></div>';
    }

    function renderTicketTypes() {
      const c = document.getElementById('ticket-list'); c.innerHTML = '';
      for (const t of ticketTypes) {
        quantities[t.id] = quantities[t.id]||0;
        const so = !t.is_available;
        const icon = t.category==='redeemable' ? (t.item_icon||'\\u{1F381}') : '\\u{1F3AB}';
        const el = document.createElement('div');
        el.className = 'ticket-type'+(so?' sold-out':'');
        el.innerHTML = '<div class="ticket-icon">'+icon+'</div><div class="ticket-info"><div class="ticket-name">'+esc(t.name)+'</div>'+(t.description?'<div class="ticket-desc">'+esc(t.description)+'</div>':'')+(t.remaining!==null?'<div class="ticket-desc">'+t.remaining+' remaining</div>':'')+'</div><div class="ticket-price">'+(t.price_cents===0?'Free':fp(t.price_cents))+'</div><div class="qty-control"><button class="qty-btn" onclick="chg(\\''+t.id+'\\', -1)" id="m-'+t.id+'" disabled>\\u2212</button><span class="qty-value" id="q-'+t.id+'">0</span><button class="qty-btn" onclick="chg(\\''+t.id+'\\', 1)" id="p-'+t.id+'"'+(so?' disabled':'')+'>+</button></div>';
        c.appendChild(el);
      }
      ub();
    }

    function chg(id, d) {
      const t = ticketTypes.find(x=>x.id===id); if(!t) return;
      const mx = 10, ma = t.remaining!==null?t.remaining:mx;
      const nq = Math.max(0,Math.min(Math.min(mx,ma),(quantities[id]||0)+d));
      quantities[id] = nq;
      document.getElementById('q-'+id).textContent = nq;
      document.getElementById('m-'+id).disabled = nq<=0;
      document.getElementById('p-'+id).disabled = nq>=Math.min(mx,ma);
      ub();
    }

    function ub() {
      const btn = document.getElementById('action-btn'), tot = tq();
      if (currentStep===0) { btn.textContent = tot>0 ? 'Continue ('+tot+' ticket'+(tot!==1?'s':'') +')' : 'Select Tickets'; btn.disabled = tot===0; }
      else if (currentStep===1) { btn.textContent = 'Continue to Payment'; btn.disabled = false; }
      else if (currentStep===2) { btn.textContent = 'Pay '+fp(ct(bc()-promoDiscount)); btn.disabled = isProcessing; }
    }

    function goTo(s) {
      document.querySelectorAll('.step-content').forEach((el,i)=>el.classList.toggle('active',i===s));
      document.querySelectorAll('.step-dot').forEach((el,i)=>{el.classList.remove('active','done');if(i<s)el.classList.add('done');if(i===s)el.classList.add('active');});
      currentStep = s;
      if(s===1) rs('summary-step1');
      if(s===2){rs('summary-step2');initStripe();}
      ub();
    }

    function handleAction() {
      if(isProcessing) return;
      if(currentStep===0){if(tq()===0) return; goTo(1);}
      else if(currentStep===1){
        const e = document.getElementById('buyer-email').value.trim();
        if(!e||!e.includes('@')){document.getElementById('buyer-email').style.borderColor='var(--error)';document.getElementById('buyer-email').focus();return;}
        document.getElementById('buyer-email').style.borderColor='';goTo(2);
      } else if(currentStep===2) processPayment();
    }

    function rs(cid) {
      const el = document.getElementById(cid); let h = '';
      for(const t of ticketTypes){const q=quantities[t.id]||0;if(q===0)continue;h+='<div class="summary-line"><span class="label">'+esc(t.name)+' \\u00D7 '+q+'</span><span>'+fp(t.price_cents*q)+'</span></div>';}
      if(promoDiscount>0) h+='<div class="summary-line"><span class="label">Promo discount</span><span style="color:var(--success)">\\u2212'+fp(promoDiscount)+'</span></div>';
      const nb = Math.max(0,bc()-promoDiscount), f = sf(nb);
      if(f>0) h+='<div class="summary-line"><span class="label">Service fee</span><span>'+fp(f)+'</span></div>';
      h+='<div class="summary-line total"><span class="label">Total</span><span>'+fp(ct(nb))+'</span></div>';
      el.innerHTML = h;
    }

    async function applyPromo() {
      const code = document.getElementById('promo-input').value.trim(); if(!code) return;
      const r = document.getElementById('promo-result'), b = document.getElementById('promo-btn');
      b.disabled=true; b.textContent='...';
      try {
        const res = await fetch(API_BASE+'/widget-validate-promo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({widget_key:WIDGET_KEY,event_id:EVENT_ID,code,base_price_cents:bc()})});
        const d = await res.json();
        if(d.valid){promoDiscount=d.discount_cents;promoCode=code;r.className='promo-result success';r.textContent='\\u2212'+fp(d.discount_cents)+' discount applied!';}
        else{promoDiscount=0;promoCode=null;r.className='promo-result error';r.textContent=d.error||'Invalid promo code';}
      }catch{r.className='promo-result error';r.textContent='Failed to validate code';}
      b.disabled=false;b.textContent='Apply';ub();
    }

    function initStripe(){if(stripeInstance)return;ccs();}

    async function ccs() {
      const btn = document.getElementById('action-btn'); btn.disabled=true; btn.textContent='Setting up payment...';
      const sel = [];
      for(const t of ticketTypes){const q=quantities[t.id]||0;if(q>0)sel.push({ticket_type_id:t.id,quantity:q});}
      try {
        const res = await fetch(API_BASE+'/widget-create-checkout',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({widget_key:WIDGET_KEY,event_id:EVENT_ID,ticket_selections:sel,buyer_email:document.getElementById('buyer-email').value.trim(),buyer_name:document.getElementById('buyer-name').value.trim()||null,promo_code:promoCode})});
        if(!res.ok){const e=await res.json();throw new Error(e.error||'Checkout failed');}
        checkoutSession = await res.json();
        stripeInstance = Stripe(checkoutSession.publishable_key);
        const elements = stripeInstance.elements();
        cardElement = elements.create('card',{style:{base:{fontSize:'15px',fontFamily:"'Inter',sans-serif",color:'#111827','::placeholder':{color:'#9CA3AF'}},invalid:{color:'#EF4444'}}});
        cardElement.mount('#card-element');
        cardElement.on('change',ev=>{document.getElementById('card-errors').textContent=ev.error?.message||'';});
        ub();
      } catch(err){document.getElementById('card-errors').textContent=err.message;btn.disabled=false;btn.textContent='Retry';}
    }

    async function processPayment() {
      if(!stripeInstance||!cardElement||!checkoutSession) return;
      isProcessing=true; const btn=document.getElementById('action-btn'); btn.disabled=true; btn.textContent='Processing...';
      try {
        const {error,paymentIntent} = await stripeInstance.confirmCardPayment(checkoutSession.client_secret,{payment_method:{card:cardElement,billing_details:{email:document.getElementById('buyer-email').value.trim(),name:document.getElementById('buyer-name').value.trim()||undefined}}});
        if(error){document.getElementById('card-errors').textContent=error.message;isProcessing=false;btn.disabled=false;ub();return;}
        if(paymentIntent.status==='succeeded') showSuccess();
        else if(paymentIntent.status==='processing') showSuccess('Your payment is processing. Tickets will arrive by email shortly.');
      }catch{document.getElementById('card-errors').textContent='Payment failed. Please try again.';isProcessing=false;btn.disabled=false;ub();}
    }

    function showSuccess(msg){
      document.getElementById('main-flow').style.display='none';
      document.getElementById('success-view').style.display='flex';
      if(msg)document.getElementById('success-message').textContent=msg;
      window.parent.postMessage({type:'tickety:checkout_complete',payload:{session_id:checkoutSession?.session_id,event_id:EVENT_ID,email:document.getElementById('buyer-email')?.value?.trim()}},'*');
    }
    function showError(msg){document.getElementById('loading-view').style.display='none';document.getElementById('error-view').style.display='flex';document.getElementById('error-message').textContent=msg;}
    function closeWidget(){window.parent.postMessage({type:'tickety:close'},'*');}
    function tq(){return Object.values(quantities).reduce((a,b)=>a+b,0);}
    function bc(){let t=0;for(const x of ticketTypes)t+=(quantities[x.id]||0)*x.price_cents;return t;}
    function sf(b){if(b<=0)return 0;const p=Math.ceil(b*0.05),s=b+p+25;return Math.ceil((s+30)/(1-0.029))-b;}
    function ct(b){if(b<=0)return 0;const p=Math.ceil(b*0.05),s=b+p+25;return Math.ceil((s+30)/(1-0.029));}
    function fp(c){return '$'+(c/100).toFixed(2);}
    function esc(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML;}
    init();
  </script>
</body>
</html>`
