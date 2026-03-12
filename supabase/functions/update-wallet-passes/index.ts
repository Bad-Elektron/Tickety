import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import { encode as base64Encode } from 'https://deno.land/std@0.177.0/encoding/base64.ts'
import { crypto } from 'https://deno.land/std@0.177.0/crypto/mod.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

const GOOGLE_WALLET_ISSUER_ID = Deno.env.get('GOOGLE_WALLET_ISSUER_ID') ?? ''
const GOOGLE_WALLET_SERVICE_ACCOUNT_KEY = Deno.env.get('GOOGLE_WALLET_SERVICE_ACCOUNT_KEY') ?? ''

/**
 * Propagates event changes to wallet passes.
 *
 * Called when event details change (time, venue, name).
 * - Apple: Sends APNs push notification → device calls webServiceURL to fetch updated pass
 * - Google: PATCH the EventTicketObject via REST API
 *
 * Body: { event_id: string }
 */
serve(async (req) => {
  try {
    const { event_id } = await req.json()

    if (!event_id) {
      return new Response(
        JSON.stringify({ error: 'Missing event_id' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Get updated event data
    const { data: event, error: eventError } = await supabase
      .from('events')
      .select('title, subtitle, date, end_time, venue, city, country, formatted_address, latitude, longitude')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      return new Response(
        JSON.stringify({ error: 'Event not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Get all wallet passes for this event's tickets
    const { data: passes } = await supabase
      .from('wallet_passes')
      .select(`
        id, pass_type, apple_serial, apple_push_token, google_object_id,
        tickets!inner (event_id)
      `)
      .eq('tickets.event_id', event_id)

    if (!passes || passes.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No passes to update', updated: 0 }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    let appleUpdated = 0
    let googleUpdated = 0

    // Process Apple passes — send APNs push notification
    const applePasses = passes.filter(p => p.pass_type === 'apple' && p.apple_push_token)
    if (applePasses.length > 0) {
      appleUpdated = await sendApplePushNotifications(applePasses)

      // Mark passes as updated so the device fetches the new version
      const appleIds = applePasses.map(p => p.id)
      await supabase
        .from('wallet_passes')
        .update({ status: 'updated', updated_at: new Date().toISOString() })
        .in('id', appleIds)
    }

    // Process Google passes — PATCH via REST API
    const googlePasses = passes.filter(p => p.pass_type === 'google' && p.google_object_id)
    if (googlePasses.length > 0) {
      googleUpdated = await updateGooglePasses(googlePasses, event)
    }

    // Re-generate the pass files for Apple (they'll be fetched when device calls webServiceURL)
    // This is handled by the webServiceURL endpoint — when the device gets the push,
    // it calls GET /v1/passes/{passTypeId}/{serialNumber} which serves the latest pass.
    // We need to regenerate the pass file with updated event details.
    for (const pass of applePasses) {
      try {
        const generateUrl = `${supabaseUrl}/functions/v1/generate-wallet-pass`
        // Get the ticket_id for this pass
        const { data: passData } = await supabase
          .from('wallet_passes')
          .select('ticket_id')
          .eq('id', pass.id)
          .single()

        if (passData) {
          // Fire-and-forget regeneration
          fetch(generateUrl, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${supabaseServiceKey}`,
            },
            body: JSON.stringify({
              ticket_id: passData.ticket_id,
              pass_type: 'apple',
            }),
          }).catch(err => console.error('Apple pass regeneration failed:', err.message))
        }
      } catch (err) {
        console.error(`Failed to regenerate Apple pass ${pass.id}:`, err.message)
      }
    }

    console.log(`Updated ${appleUpdated} Apple + ${googleUpdated} Google passes for event ${event_id}`)

    return new Response(
      JSON.stringify({
        message: 'Passes updated',
        apple_updated: appleUpdated,
        google_updated: googleUpdated,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('update-wallet-passes error:', err.message)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})

// ============================================================
// Apple Push Notifications (APNs)
// ============================================================

async function sendApplePushNotifications(
  passes: Array<Record<string, unknown>>
): Promise<number> {
  // APNs push for pass updates is an empty push notification
  // to the device, which triggers the device to call the webServiceURL
  // to fetch the updated pass.
  //
  // Requires APNs certificate or token-based auth.
  // For now, log the intent. Full APNs implementation requires
  // the Apple Push Notification service certificate.

  let count = 0
  for (const pass of passes) {
    const pushToken = pass.apple_push_token as string
    if (!pushToken) continue

    // TODO: Send actual APNs push when certificates are configured
    // The push payload for pass updates is empty: {}
    // Topic should be the passTypeIdentifier
    console.log(`Would send APNs push to device token: ${pushToken.substring(0, 8)}...`)
    count++
  }

  return count
}

// ============================================================
// Google Wallet REST API
// ============================================================

async function updateGooglePasses(
  passes: Array<Record<string, unknown>>,
  event: Record<string, unknown>
): Promise<number> {
  if (!GOOGLE_WALLET_SERVICE_ACCOUNT_KEY || !GOOGLE_WALLET_ISSUER_ID) {
    console.log('Google Wallet credentials not configured, skipping updates')
    return 0
  }

  let accessToken: string
  try {
    const serviceAccountKey = JSON.parse(GOOGLE_WALLET_SERVICE_ACCOUNT_KEY)
    accessToken = await getGoogleAccessToken(serviceAccountKey)
  } catch (err) {
    console.error('Failed to get Google access token:', err.message)
    return 0
  }

  const location = event.formatted_address ||
    [event.venue, event.city, event.country].filter(Boolean).join(', ')
  const eventDate = event.date ? new Date(event.date as string) : null

  let count = 0
  const apiBase = 'https://walletobjects.googleapis.com/walletobjects/v1'

  for (const pass of passes) {
    const objectId = pass.google_object_id as string
    if (!objectId) continue

    try {
      const patchBody: Record<string, unknown> = {
        eventName: {
          defaultValue: { language: 'en', value: event.title as string },
        },
        venue: {
          name: {
            defaultValue: {
              language: 'en',
              value: (event.venue as string) || location || 'TBA',
            },
          },
          address: {
            defaultValue: { language: 'en', value: location || '' },
          },
        },
      }

      if (eventDate) {
        patchBody.dateTime = { start: eventDate.toISOString() }
      }

      const res = await fetch(`${apiBase}/eventTicketObject/${objectId}`, {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(patchBody),
      })

      if (res.ok) {
        count++
        // Mark pass as updated
        await supabase
          .from('wallet_passes')
          .update({ status: 'updated', updated_at: new Date().toISOString() })
          .eq('google_object_id', objectId)
      } else {
        const err = await res.text()
        console.error(`Google Wallet PATCH failed for ${objectId}:`, err)
      }
    } catch (err) {
      console.error(`Failed to update Google pass ${objectId}:`, err.message)
    }
  }

  return count
}

async function getGoogleAccessToken(
  serviceAccountKey: Record<string, string>
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const claims = {
    iss: serviceAccountKey.client_email,
    scope: 'https://www.googleapis.com/auth/wallet_object.issuer',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  const jwt = await signJwt(claims, serviceAccountKey.private_key)

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  const data = await res.json()
  if (!data.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(data)}`)
  }
  return data.access_token
}

async function signJwt(
  payload: Record<string, unknown>,
  privateKeyPem: string
): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT' }

  const encode = (obj: unknown) =>
    base64Encode(new TextEncoder().encode(JSON.stringify(obj)))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '')

  const headerB64 = encode(header)
  const payloadB64 = encode(payload)
  const signingInput = `${headerB64}.${payloadB64}`

  const pemContents = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')

  const keyData = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput)
  )

  const sigB64 = base64Encode(new Uint8Array(signature))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')

  return `${signingInput}.${sigB64}`
}
