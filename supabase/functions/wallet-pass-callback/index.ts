import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

/**
 * Apple Wallet webServiceURL callback handler.
 *
 * Apple devices call these endpoints to:
 * 1. Register for push updates (POST)
 * 2. Unregister device (DELETE)
 * 3. Get latest pass (GET /v1/passes/{passTypeId}/{serialNumber})
 * 4. Get serials updated since (GET /v1/devices/{deviceId}/registrations/{passTypeId})
 *
 * See: https://developer.apple.com/documentation/walletpasses/adding_a_web_service_to_update_passes
 */
serve(async (req) => {
  const url = new URL(req.url)
  const path = url.pathname
  const method = req.method

  // Extract path parts: /functions/v1/wallet-pass-callback/v1/...
  // Apple expects: webServiceURL/v1/...
  const pathAfterCallback = path.replace(/.*wallet-pass-callback/, '')

  try {
    // POST /v1/devices/{deviceId}/registrations/{passTypeId}/{serialNumber}
    // Register a device to receive push notifications for a pass
    const registerMatch = pathAfterCallback.match(
      /^\/v1\/devices\/([^/]+)\/registrations\/([^/]+)\/([^/]+)$/
    )
    if (registerMatch && method === 'POST') {
      const [, deviceId, passTypeId, serialNumber] = registerMatch

      // Verify auth token
      const authToken = req.headers.get('Authorization')?.replace('ApplePass ', '')
      if (!authToken) {
        return new Response('Unauthorized', { status: 401 })
      }

      // Verify token matches the pass
      const { data: pass } = await supabase
        .from('wallet_passes')
        .select('apple_auth_token')
        .eq('apple_serial', serialNumber)
        .single()

      if (!pass || pass.apple_auth_token !== authToken) {
        return new Response('Unauthorized', { status: 401 })
      }

      // Get push token from body
      const body = await req.json().catch(() => ({}))
      const pushToken = body.pushToken || ''

      // Upsert registration
      await supabase
        .from('wallet_pass_registrations')
        .upsert(
          {
            serial_number: serialNumber,
            device_id: deviceId,
            push_token: pushToken,
          },
          { onConflict: 'serial_number,device_id' }
        )

      // Update push token on the pass
      if (pushToken) {
        await supabase
          .from('wallet_passes')
          .update({ apple_push_token: pushToken })
          .eq('apple_serial', serialNumber)
      }

      console.log(`Device ${deviceId} registered for pass ${serialNumber}`)
      return new Response('', { status: 201 })
    }

    // DELETE /v1/devices/{deviceId}/registrations/{passTypeId}/{serialNumber}
    // Unregister device
    if (registerMatch && method === 'DELETE') {
      const [, deviceId, , serialNumber] = registerMatch

      const authToken = req.headers.get('Authorization')?.replace('ApplePass ', '')
      if (!authToken) {
        return new Response('Unauthorized', { status: 401 })
      }

      await supabase
        .from('wallet_pass_registrations')
        .delete()
        .eq('serial_number', serialNumber)
        .eq('device_id', deviceId)

      console.log(`Device ${deviceId} unregistered for pass ${serialNumber}`)
      return new Response('', { status: 200 })
    }

    // GET /v1/passes/{passTypeId}/{serialNumber}
    // Get the latest version of a pass
    const passMatch = pathAfterCallback.match(
      /^\/v1\/passes\/([^/]+)\/([^/]+)$/
    )
    if (passMatch && method === 'GET') {
      const [, passTypeId, serialNumber] = passMatch

      const authToken = req.headers.get('Authorization')?.replace('ApplePass ', '')
      if (!authToken) {
        return new Response('Unauthorized', { status: 401 })
      }

      // Verify token
      const { data: pass } = await supabase
        .from('wallet_passes')
        .select('apple_auth_token, pass_url, updated_at')
        .eq('apple_serial', serialNumber)
        .single()

      if (!pass || pass.apple_auth_token !== authToken) {
        return new Response('Unauthorized', { status: 401 })
      }

      // Check If-Modified-Since
      const ifModifiedSince = req.headers.get('If-Modified-Since')
      if (ifModifiedSince) {
        const clientDate = new Date(ifModifiedSince)
        const passDate = new Date(pass.updated_at)
        if (passDate <= clientDate) {
          return new Response('', { status: 304 })
        }
      }

      // Fetch the PKPass file from storage and return it
      if (pass.pass_url) {
        const passPath = pass.pass_url.replace(/.*wallet-passes\//, '')
        const { data: fileData, error } = await supabase.storage
          .from('wallet-passes')
          .download(passPath)

        if (error || !fileData) {
          return new Response('Pass not found', { status: 404 })
        }

        const arrayBuffer = await fileData.arrayBuffer()
        return new Response(arrayBuffer, {
          status: 200,
          headers: {
            'Content-Type': 'application/vnd.apple.pkpass',
            'Last-Modified': new Date(pass.updated_at).toUTCString(),
          },
        })
      }

      return new Response('Pass not found', { status: 404 })
    }

    // GET /v1/devices/{deviceId}/registrations/{passTypeId}
    // Get serial numbers for passes updated since a tag
    const serialsMatch = pathAfterCallback.match(
      /^\/v1\/devices\/([^/]+)\/registrations\/([^/]+)$/
    )
    if (serialsMatch && method === 'GET') {
      const [, deviceId, passTypeId] = serialsMatch
      const passesUpdatedSince = url.searchParams.get('passesUpdatedSince')

      // Get registrations for this device
      const { data: registrations } = await supabase
        .from('wallet_pass_registrations')
        .select('serial_number')
        .eq('device_id', deviceId)

      if (!registrations || registrations.length === 0) {
        return new Response('', { status: 204 })
      }

      const serials = registrations.map(r => r.serial_number)

      // Filter by updated_since if provided
      let query = supabase
        .from('wallet_passes')
        .select('apple_serial, updated_at')
        .in_('apple_serial', serials)

      if (passesUpdatedSince) {
        query = query.gt('updated_at', passesUpdatedSince)
      }

      const { data: passes } = await query

      if (!passes || passes.length === 0) {
        return new Response('', { status: 204 })
      }

      const latestUpdate = passes.reduce((max, p) =>
        new Date(p.updated_at) > new Date(max) ? p.updated_at : max,
        passes[0].updated_at
      )

      return new Response(
        JSON.stringify({
          serialNumbers: passes.map(p => p.apple_serial),
          lastUpdated: latestUpdate,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // POST /v1/log — Apple sends error logs
    if (pathAfterCallback === '/v1/log' && method === 'POST') {
      const body = await req.json().catch(() => ({}))
      console.log('Apple Wallet log:', JSON.stringify(body))
      return new Response('', { status: 200 })
    }

    return new Response('Not found', { status: 404 })
  } catch (err) {
    console.error('wallet-pass-callback error:', err.message)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
