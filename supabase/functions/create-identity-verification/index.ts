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

/**
 * Creates a Stripe Identity VerificationSession for organizer identity verification.
 *
 * Required for organizers creating events with 250+ capacity.
 * Uses Stripe's hosted verification page for government ID + selfie checks.
 */
serve(async (req) => {
  // Handle CORS preflight
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

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Verify the user is authenticated
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check current verification status
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('identity_verification_status, stripe_identity_session_id')
      .eq('id', user.id)
      .single()

    if (profile?.identity_verification_status === 'verified') {
      return new Response(
        JSON.stringify({
          status: 'already_verified',
          message: 'Your identity is already verified',
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // If there's an existing pending session, check its status
    if (profile?.stripe_identity_session_id && profile?.identity_verification_status === 'pending') {
      try {
        const existingSession = await stripe.identity.verificationSessions.retrieve(
          profile.stripe_identity_session_id
        )

        // If session is still usable, return it
        if (existingSession.status === 'requires_input' || existingSession.status === 'created') {
          return new Response(
            JSON.stringify({
              url: existingSession.url,
              session_id: existingSession.id,
              status: 'pending',
            }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      } catch (err) {
        console.log('Existing session not reusable, creating new one:', err.message)
      }
    }

    // Create a new Stripe Identity VerificationSession
    const session = await stripe.identity.verificationSessions.create({
      type: 'document',
      metadata: {
        supabase_user_id: user.id,
        platform: 'tickety',
      },
      options: {
        document: {
          require_matching_selfie: true,
        },
      },
    })

    console.log(`Created identity verification session ${session.id} for user ${user.id}`)

    // Store session ID and set status to pending
    const { error: updateError } = await supabaseAdmin
      .from('profiles')
      .update({
        stripe_identity_session_id: session.id,
        identity_verification_status: 'pending',
      })
      .eq('id', user.id)

    if (updateError) {
      console.error('Failed to update profile with session ID:', updateError)
    }

    return new Response(
      JSON.stringify({
        url: session.url,
        session_id: session.id,
        status: 'pending',
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error creating identity verification:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Failed to create verification session' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
