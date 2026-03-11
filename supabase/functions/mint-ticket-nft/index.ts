import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import { ed25519 } from 'https://esm.sh/@noble/curves@1.3.0/ed25519'
import { sha512 } from 'https://esm.sh/@noble/hashes@1.3.3/sha512'
import { blake2b as _blake2b } from 'https://esm.sh/@noble/hashes@1.3.3/blake2b'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const blockfrostProjectId = Deno.env.get('BLOCKFROST_PROJECT_ID') || 'previewVA5jY9V686T1apRZItmlqZUf5jOEpNqB'
const platformSigningKeyHex = Deno.env.get('PLATFORM_CARDANO_SIGNING_KEY') || ''
const platformVerifyKeyHex = Deno.env.get('PLATFORM_CARDANO_VERIFY_KEY') || ''

const supabase = createClient(supabaseUrl, supabaseServiceKey)
const BLOCKFROST_BASE = 'https://cardano-preview.blockfrost.io/api/v0'

// CIP-68 label prefixes
const CIP68_REFERENCE_LABEL = '000643b0' // (100) Reference NFT
const CIP68_USER_TOKEN_LABEL = '000de140' // (222) User Token

// Ed25519 curve order
const ED25519_L = 2n ** 252n + 27742317777372353535851937790883648493n

// ====================================================================
// Platform key helpers
// ====================================================================

function getPlatformKeys(): { kL: Uint8Array; kR: Uint8Array; publicKey: Uint8Array } {
  const fullKey = hexToBytes(platformSigningKeyHex)
  const kL = fullKey.slice(0, 32)
  const kR = fullKey.length >= 64 ? fullKey.slice(32, 64) : new Uint8Array(32)
  const publicKey = platformVerifyKeyHex
    ? hexToBytes(platformVerifyKeyHex)
    : ed25519.getPublicKey(kL) // fallback (wrong for HD keys)
  return { kL, kR, publicKey }
}

// BIP32-Ed25519 signing (uses kL as scalar directly, kR for nonce)
function bip32Ed25519Sign(
  message: Uint8Array,
  kL: Uint8Array,
  kR: Uint8Array,
  publicKey: Uint8Array,
): Uint8Array {
  const a = bytesToBigIntLE(kL)

  // r = SHA-512(kR || message) mod L
  const nonceInput = new Uint8Array(kR.length + message.length)
  nonceInput.set(kR)
  nonceInput.set(message, kR.length)
  const r = modL(bytesToBigIntLE(sha512(nonceInput)))

  // R = r * G
  const R = ed25519.ExtendedPoint.BASE.multiply(r)
  const R_bytes = R.toRawBytes()

  // h = SHA-512(R || publicKey || message) mod L
  const hInput = new Uint8Array(32 + 32 + message.length)
  hInput.set(R_bytes)
  hInput.set(publicKey, 32)
  hInput.set(message, 64)
  const h = modL(bytesToBigIntLE(sha512(hInput)))

  // S = (r + h * a) mod L
  const S = modL(r + h * a)
  const S_bytes = bigIntToBytesLE(S, 32)

  const sig = new Uint8Array(64)
  sig.set(R_bytes)
  sig.set(S_bytes, 32)
  return sig
}

function modL(a: bigint): bigint {
  return ((a % ED25519_L) + ED25519_L) % ED25519_L
}

function bytesToBigIntLE(bytes: Uint8Array): bigint {
  let result = 0n
  for (let i = bytes.length - 1; i >= 0; i--) {
    result = (result << 8n) | BigInt(bytes[i])
  }
  return result
}

function bigIntToBytesLE(n: bigint, len: number): Uint8Array {
  const result = new Uint8Array(len)
  for (let i = 0; i < len; i++) {
    result[i] = Number(n & 0xffn)
    n >>= 8n
  }
  return result
}

// ====================================================================
// Blake2b (using @noble/hashes — correct implementation)
// ====================================================================

function blake2b224(input: Uint8Array): Uint8Array {
  return _blake2b(input, { dkLen: 28 })
}

function blake2b256(input: Uint8Array): Uint8Array {
  return _blake2b(input, { dkLen: 32 })
}

// ====================================================================
// Bech32
// ====================================================================

function bech32ToHex(bech32Addr: string): string {
  const CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
  const sepIndex = bech32Addr.lastIndexOf('1')
  if (sepIndex < 1) throw new Error('Invalid bech32 address')
  const dataPart = bech32Addr.substring(sepIndex + 1)
  const data5bit: number[] = []
  for (const c of dataPart) {
    const idx = CHARSET.indexOf(c)
    if (idx < 0) throw new Error('Invalid bech32 character')
    data5bit.push(idx)
  }
  const payload5bit = data5bit.slice(0, data5bit.length - 6)
  const bytes: number[] = []
  let acc = 0, bits = 0
  for (const v of payload5bit) {
    acc = (acc << 5) | v
    bits += 5
    while (bits >= 8) { bits -= 8; bytes.push((acc >> bits) & 0xff) }
  }
  return bytesToHex(new Uint8Array(bytes))
}

// ====================================================================
// Hex utilities
// ====================================================================

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < hex.length; i += 2) bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16)
  return bytes
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('')
}

function stringToHex(s: string): string {
  return bytesToHex(new TextEncoder().encode(s))
}

// ====================================================================
// CBOR encoder
// ====================================================================

function cborUint(value: number): number[] {
  if (value < 24) return [value]
  if (value < 256) return [24, value]
  if (value < 65536) return [25, value >> 8, value & 0xff]
  if (value < 4294967296) return [26, (value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff]
  const hi = Math.floor(value / 4294967296)
  const lo = value >>> 0
  return [27, (hi >>> 24) & 0xff, (hi >>> 16) & 0xff, (hi >>> 8) & 0xff, hi & 0xff,
    (lo >>> 24) & 0xff, (lo >>> 16) & 0xff, (lo >>> 8) & 0xff, lo & 0xff]
}

function cborHeader(majorType: number, value: number): number[] {
  const mt = majorType << 5
  if (value < 24) return [mt | value]
  if (value < 256) return [mt | 24, value]
  if (value < 65536) return [mt | 25, value >> 8, value & 0xff]
  return [mt | 26, (value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff]
}

function cborBytes(data: Uint8Array): number[] {
  return [...cborHeader(2, data.length), ...data]
}

function cborText(s: string): number[] {
  const enc = new TextEncoder().encode(s)
  return [...cborHeader(3, enc.length), ...enc]
}

function cborArray(items: number[][]): number[] {
  return [...cborHeader(4, items.length), ...items.flat()]
}

function cborMap(entries: [number[], number[]][]): number[] {
  return [...cborHeader(5, entries.length), ...entries.flat(2)]
}

// CBOR tag encoding
function cborTag(tagNum: number, content: number[]): number[] {
  // Tag major type = 6
  const tagHeader = cborHeader(6, tagNum)
  return [...tagHeader, ...content]
}

// ====================================================================
// NativeScript Policy
// ====================================================================

function buildPubKeyNativeScript(keyHash: Uint8Array): Uint8Array {
  const cbor = cborArray([cborUint(0), cborBytes(keyHash)])
  return new Uint8Array(cbor)
}

function computePolicyId(scriptCbor: Uint8Array): Uint8Array {
  // Alonzo+ native script hash: blake2b_224(0x00 || script_cbor)
  const prefixed = new Uint8Array(1 + scriptCbor.length)
  prefixed[0] = 0x00 // native script type tag
  prefixed.set(scriptCbor, 1)
  return blake2b224(prefixed)
}

// ====================================================================
// CIP-68 asset name
// ====================================================================

function buildAssetName(label: string, nameHex: string): string {
  return label + nameHex
}

// ====================================================================
// Transaction building (Babbage/Conway era)
// ====================================================================

function buildMintTx(params: {
  utxos: any[]
  platformAddressBytes: Uint8Array
  buyerAddressHex: string
  policyId: string
  policyScriptCbor: Uint8Array
  refAssetName: string
  userAssetName: string
  metadataDatumCbor: number[] // CBOR-encoded plutus datum
  protocolParams: any
  currentSlot: number
}): number[] {
  const {
    utxos, platformAddressBytes, buyerAddressHex, policyId,
    policyScriptCbor, refAssetName, userAssetName, metadataDatumCbor,
    protocolParams, currentSlot,
  } = params

  const minFeeA = parseInt(protocolParams.min_fee_a)
  const minFeeB = parseInt(protocolParams.min_fee_b)
  const ttl = currentSlot + 7200

  // Conservative fee estimate for mint tx (~800 bytes with witness + script)
  const estimatedFee = (900 * minFeeA) + minFeeB

  // Minimum ADA for outputs with native assets (must cover minUTxO)
  const minAdaRefOutput = 2_500_000  // 2.5 ADA for reference NFT with inline datum
  const minAdaUserOutput = 1_500_000 // 1.5 ADA for user token
  const totalNeeded = estimatedFee + minAdaRefOutput + minAdaUserOutput

  // Select UTxOs — prefer ADA-only UTxOs to avoid native asset accounting
  const adaOnlyUtxos = utxos.filter((u: any) =>
    u.amount.length === 1 && u.amount[0].unit === 'lovelace'
  )
  const selectedUtxos: any[] = []
  let totalInput = 0
  // Try ADA-only first
  for (const utxo of adaOnlyUtxos) {
    selectedUtxos.push(utxo)
    totalInput += parseInt(utxo.amount.find((a: any) => a.unit === 'lovelace')?.quantity || '0')
    if (totalInput >= totalNeeded) break
  }
  // If not enough, fall back to any UTxO
  if (totalInput < totalNeeded) {
    for (const utxo of utxos) {
      if (selectedUtxos.includes(utxo)) continue
      selectedUtxos.push(utxo)
      totalInput += parseInt(utxo.amount.find((a: any) => a.unit === 'lovelace')?.quantity || '0')
      if (totalInput >= totalNeeded) break
    }
  }

  if (totalInput < totalNeeded) {
    throw new Error(`Insufficient ADA. Need ${totalNeeded} lovelace, have ${totalInput}`)
  }

  const change = totalInput - minAdaRefOutput - minAdaUserOutput - estimatedFee
  const policyIdBytes = hexToBytes(policyId)
  const refAssetNameBytes = hexToBytes(refAssetName)
  const userAssetNameBytes = hexToBytes(userAssetName)
  const buyerAddressBytes = hexToBytes(buyerAddressHex)

  // === INPUTS (key 0) ===
  const inputs = selectedUtxos.map(utxo => cborArray([
    cborBytes(hexToBytes(utxo.tx_hash)),
    cborUint(utxo.output_index),
  ]))

  // === OUTPUTS (key 1) ===
  // Babbage/Conway: post-alonzo outputs use MAP format { 0: addr, 1: value, 2: datum_option }

  // Output 0: Reference NFT → platform address with inline datum
  const refTokenMap: [number[], number[]][] = [
    [cborBytes(refAssetNameBytes), cborUint(1)],
  ]
  const refMultiAsset: [number[], number[]][] = [
    [cborBytes(policyIdBytes), cborMap(refTokenMap)],
  ]
  const refValue = cborArray([cborUint(minAdaRefOutput), cborMap(refMultiAsset)])

  // Inline datum: datum_option = [1, #6.24(cbor_encoded_datum)]
  // Tag 24 wraps the datum CBOR as a bytestring (CBOR-in-CBOR)
  const datumWrapped = cborTag(24, cborBytes(new Uint8Array(metadataDatumCbor)))
  const datumOption = cborArray([cborUint(1), datumWrapped])

  // Post-Alonzo output as MAP
  const refOutput = cborMap([
    [cborUint(0), cborBytes(platformAddressBytes)],  // address
    [cborUint(1), refValue],                          // value
    [cborUint(2), datumOption],                       // datum_option
  ])

  // Output 1: User Token → buyer address (legacy array format, no datum)
  const userTokenMap: [number[], number[]][] = [
    [cborBytes(userAssetNameBytes), cborUint(1)],
  ]
  const userMultiAsset: [number[], number[]][] = [
    [cborBytes(policyIdBytes), cborMap(userTokenMap)],
  ]
  const userOutput = cborArray([
    cborBytes(buyerAddressBytes),
    cborArray([cborUint(minAdaUserOutput), cborMap(userMultiAsset)]),
  ])

  // Output 2: Change → platform address (legacy array format)
  const outputs = [refOutput, userOutput]
  if (change >= 1_000_000) {
    outputs.push(cborArray([
      cborBytes(platformAddressBytes),
      cborUint(change),
    ]))
  }

  // === MINT (key 9) ===
  const mintAssets: [number[], number[]][] = [
    [cborBytes(refAssetNameBytes), cborUint(1)],
    [cborBytes(userAssetNameBytes), cborUint(1)],
  ]
  const mintMap: [number[], number[]][] = [
    [cborBytes(policyIdBytes), cborMap(mintAssets)],
  ]

  // === TX BODY (map) ===
  const txBodyEntries: [number[], number[]][] = [
    [cborUint(0), cborArray(inputs)],   // inputs
    [cborUint(1), cborArray(outputs)],  // outputs
    [cborUint(2), cborUint(estimatedFee)], // fee
    [cborUint(3), cborUint(ttl)],       // ttl
    [cborUint(9), cborMap(mintMap)],     // mint
  ]

  return cborMap(txBodyEntries)
}

function buildWitnessSet(
  txBodyHash: Uint8Array,
  kL: Uint8Array,
  kR: Uint8Array,
  publicKey: Uint8Array,
  policyScriptCbor: Uint8Array,
): number[] {
  // BIP32-Ed25519 signing
  const signature = bip32Ed25519Sign(txBodyHash, kL, kR, publicKey)

  const vkeyWitness = cborArray([
    cborBytes(publicKey),
    cborBytes(signature),
  ])

  const witnessEntries: [number[], number[]][] = [
    [cborUint(0), cborArray([vkeyWitness])],                     // vkey witnesses
    [cborUint(1), cborArray([Array.from(policyScriptCbor)])],    // native scripts
  ]

  return cborMap(witnessEntries)
}

// ====================================================================
// Blockfrost API
// ====================================================================

async function blockfrostGet(path: string): Promise<any> {
  const resp = await fetch(`${BLOCKFROST_BASE}${path}`, {
    headers: { 'project_id': blockfrostProjectId },
  })
  if (!resp.ok) {
    const body = await resp.text()
    throw new Error(`Blockfrost ${path}: ${resp.status} ${body}`)
  }
  return resp.json()
}

async function blockfrostSubmitTx(cborHex: string): Promise<string> {
  const bytes = hexToBytes(cborHex)
  const resp = await fetch(`${BLOCKFROST_BASE}/tx/submit`, {
    method: 'POST',
    headers: { 'project_id': blockfrostProjectId, 'Content-Type': 'application/cbor' },
    body: bytes,
  })
  if (!resp.ok) {
    const body = await resp.text()
    throw new Error(`Blockfrost tx/submit: ${resp.status} ${body}`)
  }
  return resp.json()
}

// ====================================================================
// Main handler
// ====================================================================

serve(async (req) => {
  let queueEntry: any = null
  try {
    const { ticket_id, queue_id } = await req.json()

    if (!ticket_id && !queue_id) {
      return jsonResponse({ error: 'ticket_id or queue_id required' }, 400)
    }

    // Find queue entry
    if (queue_id) {
      const { data, error } = await supabase.from('nft_mint_queue').select('*').eq('id', queue_id).single()
      if (error || !data) return jsonResponse({ error: 'Queue entry not found' }, 404)
      queueEntry = data
    } else {
      const { data, error } = await supabase.from('nft_mint_queue').select('*')
        .eq('ticket_id', ticket_id).eq('status', 'queued')
        .order('created_at', { ascending: true }).limit(1).single()
      if (error || !data) return jsonResponse({ error: 'No queued mint for this ticket' }, 404)
      queueEntry = data
    }

    // Mark as minting
    await supabase.from('nft_mint_queue').update({ status: 'minting' }).eq('id', queueEntry.id)
    console.log(`[mint] Starting NFT mint for ticket ${queueEntry.ticket_id}`)

    // Get ticket + event
    const { data: ticket } = await supabase.from('tickets').select('*, events(*)').eq('id', queueEntry.ticket_id).single()
    if (!ticket) {
      await markFailed(queueEntry.id, 'Ticket not found')
      return jsonResponse({ error: 'Ticket not found' }, 404)
    }
    const event = ticket.events

    // 1. Platform keys
    const keys = getPlatformKeys()
    const paymentKeyHash = blake2b224(keys.publicKey)
    console.log(`[mint] Payment key hash: ${bytesToHex(paymentKeyHash)}`)

    // Read platform address from DB
    const { data: configRows } = await supabase.from('platform_cardano_config').select('key, value')
    const configMap: Record<string, string> = {}
    for (const row of configRows ?? []) configMap[row.key] = row.value
    const platformAddress = configMap.minting_address
    if (!platformAddress) {
      await markFailed(queueEntry.id, 'No minting_address in platform_cardano_config')
      return jsonResponse({ error: 'Platform address not configured' }, 500)
    }
    const platformAddressBytes = hexToBytes(bech32ToHex(platformAddress))
    console.log(`[mint] Platform address: ${platformAddress}`)

    // 2. Native script policy
    const policyScriptCbor = buildPubKeyNativeScript(paymentKeyHash)
    const policyId = bytesToHex(computePolicyId(policyScriptCbor))
    console.log(`[mint] Policy ID: ${policyId}`)

    // 3. CIP-68 asset names
    const ticketName = `TCKT${ticket.ticket_number.replace(/[^A-Za-z0-9]/g, '')}`
    const nameHex = stringToHex(ticketName)
    const refAssetName = buildAssetName(CIP68_REFERENCE_LABEL, nameHex)
    const userAssetName = buildAssetName(CIP68_USER_TOKEN_LABEL, nameHex)
    console.log(`[mint] Asset: ref=${refAssetName}, user=${userAssetName}`)

    // 4. CIP-68 metadata datum (Constr 0 [metadata_map, version, extra])
    // Plutus data only supports: int, bytes, list, map, constr — NO text strings
    // All strings must be encoded as byte strings
    const textAsBytes = (s: string) => cborBytes(new TextEncoder().encode(s))
    const metadataFields: [number[], number[]][] = [
      [textAsBytes('name'), textAsBytes(`Tickety #${ticket.ticket_number}`)],
      [textAsBytes('event'), textAsBytes(event.title)],
      [textAsBytes('event_id'), textAsBytes(event.id)],
      [textAsBytes('ticket_number'), textAsBytes(ticket.ticket_number)],
      [textAsBytes('ticket_id'), textAsBytes(ticket.id)],
    ]
    if (event.date) metadataFields.push([textAsBytes('event_date'), textAsBytes(event.date)])
    if (event.venue) metadataFields.push([textAsBytes('venue'), textAsBytes(event.venue)])

    // CIP-68 datum: #6.121([metadata_map, version, extra])
    // Constructor 0 = tag 121
    // Plutus data types: int, bytes, list, map, constr — NO null
    const metadataDatumCbor = [
      0xd8, 0x79, // tag(121)
      ...cborArray([
        cborMap(metadataFields),
        cborUint(1),                          // version
        cborBytes(new Uint8Array(0)),         // extra = empty bytestring
      ]),
    ]

    // 5. Fetch UTxOs + protocol params + latest block
    const [utxos, protocolParams, latestBlock] = await Promise.all([
      blockfrostGet(`/addresses/${platformAddress}/utxos`).catch((err: Error) => {
        console.error(`[mint] UTxO fetch failed: ${err.message}`)
        return null
      }),
      blockfrostGet('/epochs/latest/parameters'),
      blockfrostGet('/blocks/latest'),
    ])

    console.log(`[mint] UTxOs: ${utxos === null ? 'FETCH_FAILED' : `${Array.isArray(utxos) ? utxos.length : 'not-array'}`}`)

    if (!utxos || (Array.isArray(utxos) && utxos.length === 0)) {
      const reason = utxos === null ? 'Blockfrost API failed' : 'Platform wallet has no UTxOs'
      await markFailed(queueEntry.id, reason)
      return jsonResponse({ error: reason }, 503)
    }

    // 6. Build mint transaction
    const buyerAddressHex = bech32ToHex(queueEntry.buyer_address)

    const txBody = buildMintTx({
      utxos,
      platformAddressBytes,
      buyerAddressHex,
      policyId,
      policyScriptCbor,
      refAssetName,
      userAssetName,
      metadataDatumCbor,
      protocolParams,
      currentSlot: latestBlock.slot,
    })

    // 7. Hash and sign
    const txBodyBytes = new Uint8Array(txBody)
    const txBodyHash = blake2b256(txBodyBytes)
    console.log(`[mint] Tx body hash: ${bytesToHex(txBodyHash)} (${txBodyBytes.length} bytes)`)

    const witnessSet = buildWitnessSet(txBodyHash, keys.kL, keys.kR, keys.publicKey, policyScriptCbor)

    // Full signed transaction: [body, witness_set, is_valid, auxiliary_data]
    const signedTx = cborArray([txBody, witnessSet, [0xf5], [0xf6]])
    const signedTxHex = bytesToHex(new Uint8Array(signedTx))
    console.log(`[mint] Submitting tx (${signedTxHex.length / 2} bytes)...`)

    // 8. Submit
    const txHash = await blockfrostSubmitTx(signedTxHex)
    console.log(`[mint] Tx submitted: ${txHash}`)

    // 9. Update DB
    const refAssetId = policyId + refAssetName
    const userAssetId = policyId + userAssetName

    await supabase.from('nft_mint_queue').update({
      status: 'minted', tx_hash: txHash, policy_id: policyId,
      reference_asset_id: refAssetId, user_asset_id: userAssetId,
    }).eq('id', queueEntry.id)

    await supabase.from('tickets').update({
      nft_minted: true, nft_asset_id: userAssetId,
      nft_minted_at: new Date().toISOString(),
      nft_policy_id: policyId, nft_tx_hash: txHash,
    }).eq('id', queueEntry.ticket_id)

    if (!event.nft_policy_id) {
      await supabase.from('events').update({ nft_policy_id: policyId }).eq('id', event.id)
    }

    return jsonResponse({
      success: true, tx_hash: txHash, policy_id: policyId,
      user_asset_id: userAssetId, reference_asset_id: refAssetId,
    })

  } catch (err) {
    console.error('[mint] Error:', err)
    try {
      if (queueEntry?.id) {
        await markFailed(queueEntry.id, err.message)
      }
    } catch (_) {}
    return jsonResponse({ error: err.message }, 500)
  }
})

const MAX_RETRIES = 5

async function markFailed(queueId: string, errorMessage: string) {
  const { data } = await supabase.from('nft_mint_queue').select('retry_count').eq('id', queueId).single()
  const retryCount = (data?.retry_count || 0) + 1

  if (retryCount > MAX_RETRIES) {
    // Give up after max retries — needs manual intervention
    await supabase.from('nft_mint_queue').update({
      status: 'failed',
      error_message: `Gave up after ${retryCount} retries: ${errorMessage}`,
      retry_count: retryCount,
    }).eq('id', queueId)
    console.error(`[mint] Permanently failed ${queueId} after ${retryCount} retries`)
    return
  }

  // Reset to queued so next invocation picks it up
  await supabase.from('nft_mint_queue').update({
    status: 'queued',
    error_message: `Retry #${retryCount}: ${errorMessage}`,
    retry_count: retryCount,
  }).eq('id', queueId)

  console.log(`[mint] Reset ${queueId} to queued (retry #${retryCount})`)

  // Fire-and-forget self-invoke for immediate retry
  // Use waitUntil pattern: fetch starts but we don't await the full response
  fetch(`${supabaseUrl}/functions/v1/mint-ticket-nft`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${supabaseServiceKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ queue_id: queueId }),
  }).catch(err => console.error(`[mint] Retry invocation failed: ${err}`))
}

function jsonResponse(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}
