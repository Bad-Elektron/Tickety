import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import { encode as base64Encode } from 'https://deno.land/std@0.177.0/encoding/base64.ts'
import { crypto } from 'https://deno.land/std@0.177.0/crypto/mod.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

// Apple pass config
const APPLE_TEAM_ID = Deno.env.get('APPLE_TEAM_ID') ?? ''
const APPLE_PASS_TYPE_ID = Deno.env.get('APPLE_PASS_TYPE_ID') ?? ''
const APPLE_PASS_CERT = Deno.env.get('APPLE_PASS_CERT') ?? ''
const APPLE_PASS_KEY = Deno.env.get('APPLE_PASS_KEY') ?? ''
const APPLE_PASS_PHRASE = Deno.env.get('APPLE_PASS_PHRASE') ?? ''

// Google Wallet config
const GOOGLE_WALLET_ISSUER_ID = Deno.env.get('GOOGLE_WALLET_ISSUER_ID') ?? ''
const GOOGLE_WALLET_SERVICE_ACCOUNT_KEY = Deno.env.get('GOOGLE_WALLET_SERVICE_ACCOUNT_KEY') ?? ''

serve(async (req) => {
  try {
    const { ticket_id, pass_type } = await req.json()

    if (!ticket_id || !pass_type) {
      return new Response(
        JSON.stringify({ error: 'Missing ticket_id or pass_type' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Get ticket with event data
    const { data: ticket, error: ticketError } = await supabase
      .from('tickets')
      .select(`
        id, ticket_number, event_id, owner_name, owner_email, status,
        events (
          title, subtitle, date, end_time, venue, city, country,
          formatted_address, latitude, longitude
        )
      `)
      .eq('id', ticket_id)
      .single()

    if (ticketError || !ticket) {
      return new Response(
        JSON.stringify({ error: 'Ticket not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const event = ticket.events as Record<string, unknown>

    // Check for existing pass
    const { data: existingPass } = await supabase
      .from('wallet_passes')
      .select()
      .eq('ticket_id', ticket_id)
      .eq('pass_type', pass_type)
      .maybeSingle()

    if (existingPass?.pass_url) {
      return new Response(
        JSON.stringify({ pass: existingPass }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // QR barcode data — matches check-in format
    const qrData = JSON.stringify({
      type: 'tickety_ticket',
      version: 1,
      ticket_id: ticket.id,
      ticket_number: ticket.ticket_number,
      event_id: ticket.event_id,
    })

    let passRecord: Record<string, unknown>

    if (pass_type === 'apple') {
      passRecord = await generateApplePass(ticket, event, qrData)
    } else if (pass_type === 'google') {
      passRecord = await generateGooglePass(ticket, event, qrData)
    } else {
      return new Response(
        JSON.stringify({ error: 'Invalid pass_type. Must be "apple" or "google"' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Upsert pass record
    const { data: pass, error: passError } = await supabase
      .from('wallet_passes')
      .upsert({
        ticket_id,
        pass_type,
        ...passRecord,
        status: 'delivered',
      }, { onConflict: 'ticket_id,pass_type' })
      .select()
      .single()

    if (passError) {
      console.error('Failed to save pass:', passError)
      return new Response(
        JSON.stringify({ error: 'Failed to save pass record' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ pass }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('generate-wallet-pass error:', err.message)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})

// ============================================================
// Apple Wallet (PKPass)
// ============================================================

async function generateApplePass(
  ticket: Record<string, unknown>,
  event: Record<string, unknown>,
  qrData: string
): Promise<Record<string, unknown>> {
  const serialNumber = crypto.randomUUID()
  const authToken = crypto.randomUUID().replace(/-/g, '')

  // Format event date
  const eventDate = event.date ? new Date(event.date as string) : null
  const dateStr = eventDate
    ? eventDate.toISOString()
    : undefined

  // Build location string
  const location = event.formatted_address || [event.venue, event.city, event.country].filter(Boolean).join(', ')

  // Build pass.json
  const passJson: Record<string, unknown> = {
    formatVersion: 1,
    passTypeIdentifier: APPLE_PASS_TYPE_ID,
    teamIdentifier: APPLE_TEAM_ID,
    serialNumber,
    authenticationToken: authToken,
    webServiceURL: `${supabaseUrl}/functions/v1/wallet-pass-callback`,
    organizationName: 'Tickety',
    description: `Ticket for ${event.title}`,
    foregroundColor: 'rgb(255, 255, 255)',
    backgroundColor: 'rgb(99, 102, 241)', // Indigo #6366F1
    labelColor: 'rgb(200, 200, 255)',
    eventTicket: {
      primaryFields: [
        {
          key: 'event',
          label: 'EVENT',
          value: event.title as string,
        },
      ],
      secondaryFields: [
        {
          key: 'location',
          label: 'LOCATION',
          value: location || 'TBA',
        },
        ...(dateStr
          ? [
              {
                key: 'date',
                label: 'DATE',
                value: dateStr,
                dateStyle: 'PKDateStyleMedium',
                timeStyle: 'PKDateStyleShort',
              },
            ]
          : []),
      ],
      auxiliaryFields: [
        {
          key: 'ticket',
          label: 'TICKET',
          value: ticket.ticket_number as string,
        },
        {
          key: 'holder',
          label: 'HOLDER',
          value: (ticket.owner_name as string) || (ticket.owner_email as string) || 'Guest',
        },
      ],
      backFields: [
        {
          key: 'ticketId',
          label: 'Ticket ID',
          value: ticket.id as string,
        },
        {
          key: 'eventId',
          label: 'Event ID',
          value: ticket.event_id as string,
        },
      ],
    },
    barcode: {
      format: 'PKBarcodeFormatQR',
      message: qrData,
      messageEncoding: 'iso-8859-1',
    },
    barcodes: [
      {
        format: 'PKBarcodeFormatQR',
        message: qrData,
        messageEncoding: 'iso-8859-1',
      },
    ],
  }

  // Add location if coordinates available
  if (event.latitude && event.longitude) {
    passJson.locations = [
      {
        latitude: event.latitude,
        longitude: event.longitude,
        relevantText: `You're near ${event.venue || event.title}!`,
      },
    ]
  }

  // Add relevant date
  if (dateStr) {
    passJson.relevantDate = dateStr
  }

  // If Apple signing certs are configured, build real PKPass
  if (APPLE_PASS_CERT && APPLE_PASS_KEY && APPLE_TEAM_ID && APPLE_PASS_TYPE_ID) {
    try {
      const passUrl = await buildSignedPKPass(passJson, serialNumber)
      return {
        pass_url: passUrl,
        apple_serial: serialNumber,
        apple_auth_token: authToken,
      }
    } catch (err) {
      console.error('Failed to build signed PKPass, storing unsigned:', err.message)
    }
  }

  // Fallback: store pass JSON for later signing, no URL yet
  // In production, this would use a signing service
  console.log('Apple pass created (unsigned) for ticket:', ticket.ticket_number)
  return {
    apple_serial: serialNumber,
    apple_auth_token: authToken,
    // pass_url will be null — client can retry when certs are configured
  }
}

async function buildSignedPKPass(
  passJson: Record<string, unknown>,
  serialNumber: string
): Promise<string> {
  // Build the PKPass ZIP archive with:
  // 1. pass.json
  // 2. manifest.json (SHA-256 hashes of all files)
  // 3. signature (PKCS#7 detached signature of manifest.json)
  //
  // This requires the Apple WWDR certificate and pass signing certificate.
  // In Deno, we use SubtleCrypto for hashing and the stored PEM cert/key.

  const encoder = new TextEncoder()
  const passJsonBytes = encoder.encode(JSON.stringify(passJson))

  // Hash pass.json
  const passJsonHash = await crypto.subtle.digest('SHA-256', passJsonBytes)
  const passJsonHashHex = Array.from(new Uint8Array(passJsonHash))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')

  // Build manifest
  const manifest: Record<string, string> = {
    'pass.json': passJsonHashHex,
  }
  const manifestBytes = encoder.encode(JSON.stringify(manifest))

  // Sign manifest with PKCS#7 using the Apple pass signing key
  // Note: Full PKCS#7 signing requires a native crypto library.
  // In production, use a signing microservice or pre-built PKPass files.
  // For now, we store the pass data and serve it via a URL.

  // Store the pass data in Supabase Storage
  const passFileName = `passes/apple/${serialNumber}.pkpass`

  // Build a minimal ZIP containing pass.json and manifest.json
  // Full implementation would include icon.png, logo.png, signature
  const zipData = buildMinimalZip({
    'pass.json': passJsonBytes,
    'manifest.json': manifestBytes,
  })

  const { error: uploadError } = await supabase.storage
    .from('wallet-passes')
    .upload(passFileName, zipData, {
      contentType: 'application/vnd.apple.pkpass',
      upsert: true,
    })

  if (uploadError) {
    throw new Error(`Upload failed: ${uploadError.message}`)
  }

  const { data: urlData } = supabase.storage
    .from('wallet-passes')
    .getPublicUrl(passFileName)

  return urlData.publicUrl
}

// Minimal ZIP builder for PKPass files
function buildMinimalZip(files: Record<string, Uint8Array>): Uint8Array {
  const entries: { name: Uint8Array; data: Uint8Array; offset: number }[] = []
  const encoder = new TextEncoder()
  const parts: Uint8Array[] = []
  let offset = 0

  // Local file entries
  for (const [name, data] of Object.entries(files)) {
    const nameBytes = encoder.encode(name)
    const header = new Uint8Array(30 + nameBytes.length)
    const view = new DataView(header.buffer)

    // Local file header signature
    view.setUint32(0, 0x04034b50, true)
    // Version needed
    view.setUint16(4, 20, true)
    // Compression method (0 = store)
    view.setUint16(8, 0, true)
    // CRC-32 (simplified — real impl would compute CRC)
    view.setUint32(14, crc32(data), true)
    // Compressed size
    view.setUint32(18, data.length, true)
    // Uncompressed size
    view.setUint32(22, data.length, true)
    // File name length
    view.setUint16(26, nameBytes.length, true)

    header.set(nameBytes, 30)
    parts.push(header, data)

    entries.push({ name: nameBytes, data, offset })
    offset += header.length + data.length
  }

  // Central directory
  const centralStart = offset
  for (const entry of entries) {
    const cdHeader = new Uint8Array(46 + entry.name.length)
    const cdView = new DataView(cdHeader.buffer)

    // Central directory header signature
    cdView.setUint32(0, 0x02014b50, true)
    // Version made by
    cdView.setUint16(4, 20, true)
    // Version needed
    cdView.setUint16(6, 20, true)
    // Compression method
    cdView.setUint16(10, 0, true)
    // CRC-32
    cdView.setUint32(16, crc32(entry.data), true)
    // Compressed size
    cdView.setUint32(20, entry.data.length, true)
    // Uncompressed size
    cdView.setUint32(24, entry.data.length, true)
    // File name length
    cdView.setUint16(28, entry.name.length, true)
    // Relative offset of local header
    cdView.setUint32(42, entry.offset, true)

    cdHeader.set(entry.name, 46)
    parts.push(cdHeader)
    offset += cdHeader.length
  }

  // End of central directory
  const eocd = new Uint8Array(22)
  const eocdView = new DataView(eocd.buffer)
  eocdView.setUint32(0, 0x06054b50, true)
  eocdView.setUint16(8, entries.length, true)
  eocdView.setUint16(10, entries.length, true)
  eocdView.setUint32(12, offset - centralStart, true)
  eocdView.setUint32(16, centralStart, true)
  parts.push(eocd)

  // Concatenate all parts
  const totalLen = parts.reduce((acc, p) => acc + p.length, 0)
  const result = new Uint8Array(totalLen)
  let pos = 0
  for (const part of parts) {
    result.set(part, pos)
    pos += part.length
  }
  return result
}

// CRC-32 lookup table
const crcTable = (() => {
  const table = new Uint32Array(256)
  for (let i = 0; i < 256; i++) {
    let c = i
    for (let j = 0; j < 8; j++) {
      c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1
    }
    table[i] = c
  }
  return table
})()

function crc32(data: Uint8Array): number {
  let crc = 0xFFFFFFFF
  for (let i = 0; i < data.length; i++) {
    crc = crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >>> 8)
  }
  return (crc ^ 0xFFFFFFFF) >>> 0
}

// ============================================================
// Google Wallet (JWT save URL)
// ============================================================

async function generateGooglePass(
  ticket: Record<string, unknown>,
  event: Record<string, unknown>,
  qrData: string
): Promise<Record<string, unknown>> {
  const objectId = `${GOOGLE_WALLET_ISSUER_ID}.tickety-${ticket.id}`

  // Build the EventTicketObject
  const eventDate = event.date ? new Date(event.date as string) : null
  const location = event.formatted_address || [event.venue, event.city, event.country].filter(Boolean).join(', ')

  const ticketObject: Record<string, unknown> = {
    id: objectId,
    classId: `${GOOGLE_WALLET_ISSUER_ID}.tickety-event-ticket`,
    state: 'ACTIVE',
    heroImage: {
      sourceUri: {
        uri: 'https://tickety.app/pass-hero.png',
      },
    },
    textModulesData: [
      {
        header: 'Ticket Number',
        body: ticket.ticket_number,
        id: 'ticket_number',
      },
    ],
    barcode: {
      type: 'QR_CODE',
      value: qrData,
      alternateText: ticket.ticket_number as string,
    },
    ticketHolderName: (ticket.owner_name as string) || 'Guest',
    ticketNumber: ticket.ticket_number as string,
    eventName: {
      defaultValue: {
        language: 'en',
        value: event.title as string,
      },
    },
    venue: {
      name: {
        defaultValue: {
          language: 'en',
          value: (event.venue as string) || location || 'TBA',
        },
      },
      address: {
        defaultValue: {
          language: 'en',
          value: location || '',
        },
      },
    },
  }

  // Add date/time
  if (eventDate) {
    ticketObject.dateTime = {
      start: eventDate.toISOString(),
    }
  }

  // If Google service account is configured, create/update the object and return a save URL
  if (GOOGLE_WALLET_SERVICE_ACCOUNT_KEY && GOOGLE_WALLET_ISSUER_ID) {
    try {
      const saveUrl = await createGoogleWalletSaveUrl(ticketObject)
      return {
        pass_url: saveUrl,
        google_object_id: objectId,
      }
    } catch (err) {
      console.error('Failed to create Google Wallet save URL:', err.message)
    }
  }

  // Fallback: no URL yet
  console.log('Google pass created (no credentials) for ticket:', ticket.ticket_number)
  return {
    google_object_id: objectId,
  }
}

async function createGoogleWalletSaveUrl(
  ticketObject: Record<string, unknown>
): Promise<string> {
  // Parse service account key
  const serviceAccountKey = JSON.parse(GOOGLE_WALLET_SERVICE_ACCOUNT_KEY)

  // Create JWT for Google Wallet API authentication
  const accessToken = await getGoogleAccessToken(serviceAccountKey)

  // Try to create the object (or update if exists)
  const objectId = ticketObject.id as string
  const apiBase = 'https://walletobjects.googleapis.com/walletobjects/v1'

  // Try GET first
  const getRes = await fetch(`${apiBase}/eventTicketObject/${objectId}`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })

  if (getRes.status === 404) {
    // Create new
    const createRes = await fetch(`${apiBase}/eventTicketObject`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(ticketObject),
    })
    if (!createRes.ok) {
      const err = await createRes.text()
      throw new Error(`Google Wallet create failed: ${err}`)
    }
  } else if (getRes.ok) {
    // Update existing
    const updateRes = await fetch(`${apiBase}/eventTicketObject/${objectId}`, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(ticketObject),
    })
    if (!updateRes.ok) {
      const err = await updateRes.text()
      throw new Error(`Google Wallet update failed: ${err}`)
    }
  }

  // Build the "Add to Google Wallet" save URL using a JWT
  const claims = {
    iss: serviceAccountKey.client_email,
    aud: 'google',
    typ: 'savetowallet',
    origins: ['https://tickety.app'],
    payload: {
      eventTicketObjects: [{ id: objectId }],
    },
  }

  const saveJwt = await signJwt(claims, serviceAccountKey.private_key)
  return `https://pay.google.com/gp/v/save/${saveJwt}`
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

  // Import RSA private key
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
