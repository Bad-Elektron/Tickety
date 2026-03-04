import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ManageBankRequest {
  action: 'list' | 'remove' | 'save'
  payment_method_id?: string
  setup_intent_id?: string
  bank_name?: string
  last4?: string
  account_type?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseClient = createClient(supabaseUrl, supabaseServiceKey, {
      global: { headers: { Authorization: authHeader } }
    })

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)
    const body: ManageBankRequest = await req.json()

    switch (body.action) {
      case 'list': {
        const { data: accounts } = await supabaseAdmin
          .from('linked_bank_accounts')
          .select('*')
          .eq('user_id', user.id)
          .eq('status', 'active')
          .order('is_default', { ascending: false })

        return new Response(
          JSON.stringify({ bank_accounts: accounts || [] }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      case 'save': {
        console.log(`[save] Input: payment_method_id=${body.payment_method_id}, setup_intent_id=${body.setup_intent_id}`)

        let paymentMethodId = body.payment_method_id
        let bankName = body.bank_name || 'Bank Account'
        let last4 = body.last4 || '****'
        let accountType = body.account_type || 'checking'

        // If setup_intent_id provided, resolve the payment method from Stripe
        if (!paymentMethodId && body.setup_intent_id) {
          console.log(`[save] Resolving payment method from SetupIntent ${body.setup_intent_id}...`)
          const setupIntent = await stripe.setupIntents.retrieve(body.setup_intent_id)
          console.log(`[save] SetupIntent status=${setupIntent.status}, payment_method=${JSON.stringify(setupIntent.payment_method)}`)
          if (typeof setupIntent.payment_method === 'string') {
            paymentMethodId = setupIntent.payment_method
          } else if (setupIntent.payment_method?.id) {
            paymentMethodId = setupIntent.payment_method.id
          }
          console.log(`[save] Resolved paymentMethodId=${paymentMethodId}`)
        }

        if (!paymentMethodId) {
          return new Response(
            JSON.stringify({ error: 'Missing payment_method_id or setup_intent_id' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        // Fetch bank details from Stripe payment method
        try {
          const pm = await stripe.paymentMethods.retrieve(paymentMethodId)
          if (pm.us_bank_account) {
            bankName = pm.us_bank_account.bank_name || bankName
            last4 = pm.us_bank_account.last4 || last4
            accountType = pm.us_bank_account.account_type || accountType
          }
        } catch (err) {
          console.error('Failed to retrieve payment method details:', err.message)
          // Continue with defaults
        }

        // Check if this is the first bank account (make it default)
        const { data: existingAccounts } = await supabaseAdmin
          .from('linked_bank_accounts')
          .select('id')
          .eq('user_id', user.id)
          .eq('status', 'active')

        const isFirst = !existingAccounts || existingAccounts.length === 0

        const { data: saved, error: saveError } = await supabaseAdmin
          .from('linked_bank_accounts')
          .upsert({
            user_id: user.id,
            stripe_payment_method_id: paymentMethodId,
            bank_name: bankName,
            last4: last4,
            account_type: accountType,
            is_default: isFirst,
            status: 'active',
          }, {
            onConflict: 'stripe_payment_method_id',
          })
          .select()
          .single()

        if (saveError) {
          console.error('Failed to save bank account:', saveError)
          return new Response(
            JSON.stringify({ error: 'Failed to save bank account' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        console.log(`Bank account saved for user ${user.id}: ${paymentMethodId}`)

        return new Response(
          JSON.stringify({ bank_account: saved }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      case 'remove': {
        if (!body.payment_method_id) {
          return new Response(
            JSON.stringify({ error: 'Missing payment_method_id' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        // Verify the bank account belongs to this user
        const { data: account } = await supabaseAdmin
          .from('linked_bank_accounts')
          .select('id')
          .eq('user_id', user.id)
          .eq('stripe_payment_method_id', body.payment_method_id)
          .eq('status', 'active')
          .maybeSingle()

        if (!account) {
          return new Response(
            JSON.stringify({ error: 'Bank account not found' }),
            { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        // Detach from Stripe
        try {
          await stripe.paymentMethods.detach(body.payment_method_id)
        } catch (err) {
          console.error('Failed to detach payment method from Stripe:', err.message)
          // Continue — still mark as removed in our DB
        }

        // Mark as removed in DB
        await supabaseAdmin
          .from('linked_bank_accounts')
          .update({ status: 'removed' })
          .eq('stripe_payment_method_id', body.payment_method_id)

        console.log(`Bank account removed for user ${user.id}: ${body.payment_method_id}`)

        return new Response(
          JSON.stringify({ success: true }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      default:
        return new Response(
          JSON.stringify({ error: 'Invalid action. Use: list, save, remove' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }

  } catch (error) {
    console.error('Error managing bank accounts:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
