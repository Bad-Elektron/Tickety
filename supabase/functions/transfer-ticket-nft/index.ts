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
const CIP68_REFERENCE_LABEL = '000643b0'
const CIP68_USER_TOKEN_LABEL = '000de140'

const ED25519_L = 2n ** 252n + 27742317777372353535851937790883648493n

// ====================================================================
// Platform key helpers (same as mint-ticket-nft)
// ====================================================================

function getPlatformKeys(): { kL: Uint8Array; kR: Uint8Array; publicKey: Uint8Array } {
  const fullKey = hexToBytes(platformSigningKeyHex)
  const kL = fullKey.slice(0, 32)
  const kR = fullKey.length >= 64 ? fullKey.slice(32, 64) : new Uint8Array(32)
  const publicKey = platformVerifyKeyHex
    ? hexToBytes(platformVerifyKeyHex)
    : ed25519.getPublicKey(kL)
  return { kL, kR, publicKey }
}

function bip32Ed25519Sign(
  message: Uint8Array, kL: Uint8Array, kR: Uint8Array, publicKey: Uint8Array,
): Uint8Array {
  const a = bytesToBigIntLE(kL)
  const nonceInput = new Uint8Array(kR.length + message.length)
  nonceInput.set(kR); nonceInput.set(message, kR.length)
  const r = modL(bytesToBigIntLE(sha512(nonceInput)))
  const R = ed25519.ExtendedPoint.BASE.multiply(r)
  const R_bytes = R.toRawBytes()
  const hInput = new Uint8Array(32 + 32 + message.length)
  hInput.set(R_bytes); hInput.set(publicKey, 32); hInput.set(message, 64)
  const h = modL(bytesToBigIntLE(sha512(hInput)))
  const S = modL(r + h * a)
  const sig = new Uint8Array(64)
  sig.set(R_bytes); sig.set(bigIntToBytesLE(S, 32), 32)
  return sig
}

function modL(a: bigint): bigint { return ((a % ED25519_L) + ED25519_L) % ED25519_L }
function bytesToBigIntLE(bytes: Uint8Array): bigint {
  let result = 0n
  for (let i = bytes.length - 1; i >= 0; i--) result = (result << 8n) | BigInt(bytes[i])
  return result
}
function bigIntToBytesLE(n: bigint, len: number): Uint8Array {
  const result = new Uint8Array(len)
  for (let i = 0; i < len; i++) { result[i] = Number(n & 0xffn); n >>= 8n }
  return result
}

// ====================================================================
// Blake2b
// ====================================================================

function blake2b224(input: Uint8Array): Uint8Array { return _blake2b(input, { dkLen: 28 }) }
function blake2b256(input: Uint8Array): Uint8Array { return _blake2b(input, { dkLen: 32 }) }

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
    acc = (acc << 5) | v; bits += 5
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
function stringToHex(s: string): string { return bytesToHex(new TextEncoder().encode(s)) }

// ====================================================================
// CBOR encoder
// ====================================================================

function cborUint(value: number): number[] {
  if (value < 24) return [value]
  if (value < 256) return [24, value]
  if (value < 65536) return [25, value >> 8, value & 0xff]
  if (value < 4294967296) return [26, (value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff]
  const hi = Math.floor(value / 4294967296); const lo = value >>> 0
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
function cborBytes(data: Uint8Array): number[] { return [...cborHeader(2, data.length), ...data] }
function cborArray(items: number[][]): number[] { return [...cborHeader(4, items.length), ...items.flat()] }
function cborMap(entries: [number[], number[]][]): number[] { return [...cborHeader(5, entries.length), ...entries.flat(2)] }
function cborTag(tagNum: number, content: number[]): number[] { return [...cborHeader(6, tagNum), ...content] }

// ====================================================================
// NativeScript Policy
// ====================================================================

function buildPubKeyNativeScript(keyHash: Uint8Array): Uint8Array {
  return new Uint8Array(cborArray([cborUint(0), cborBytes(keyHash)]))
}
function computePolicyId(scriptCbor: Uint8Array): Uint8Array {
  const prefixed = new Uint8Array(1 + scriptCbor.length)
  prefixed[0] = 0x00
  prefixed.set(scriptCbor, 1)
  return blake2b224(prefixed)
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
// Build transfer transaction
// ====================================================================
// Transfer = mint new user token to buyer + move reference NFT (update datum)
// The seller's old user token becomes stale — reference datum is source of truth.

function buildTransferTx(params: {
  utxos: any[]               // Platform address UTxOs (includes reference NFT)
  refUtxo: any               // The specific UTxO holding the reference NFT
  platformAddressBytes: Uint8Array
  buyerAddressHex: string
  policyId: string
  policyScriptCbor: Uint8Array
  refAssetName: string       // Reference NFT asset name (000643b0...)
  userAssetName: string      // User token asset name (000de140...)
  metadataDatumCbor: number[] // Updated CIP-68 datum with new owner
  protocolParams: any
  currentSlot: number
}): number[] {
  const {
    utxos, refUtxo, platformAddressBytes, buyerAddressHex, policyId,
    policyScriptCbor, refAssetName, userAssetName, metadataDatumCbor,
    protocolParams, currentSlot,
  } = params

  const minFeeA = parseInt(protocolParams.min_fee_a)
  const minFeeB = parseInt(protocolParams.min_fee_b)
  const ttl = currentSlot + 7200

  // Fee estimate: transfer tx is similar size to mint tx
  const estimatedFee = (900 * minFeeA) + minFeeB
  const minAdaRefOutput = 2_500_000  // Reference NFT with inline datum
  const minAdaUserOutput = 1_500_000 // New user token for buyer
  const totalNeeded = estimatedFee + minAdaRefOutput + minAdaUserOutput

  // The reference NFT UTxO is always included as an input
  const selectedUtxos: any[] = [refUtxo]
  let totalInput = 0

  // Sum ADA from the reference NFT UTxO
  const refLovelace = parseInt(refUtxo.amount.find((a: any) => a.unit === 'lovelace')?.quantity || '0')
  totalInput += refLovelace

  // Select additional ADA-only UTxOs for fees + new user token output
  const adaOnlyUtxos = utxos.filter((u: any) =>
    u.tx_hash !== refUtxo.tx_hash || u.output_index !== refUtxo.output_index
  ).filter((u: any) => u.amount.length === 1 && u.amount[0].unit === 'lovelace')

  for (const utxo of adaOnlyUtxos) {
    if (totalInput >= totalNeeded) break
    selectedUtxos.push(utxo)
    totalInput += parseInt(utxo.amount.find((a: any) => a.unit === 'lovelace')?.quantity || '0')
  }

  // Fall back to any UTxO if needed
  if (totalInput < totalNeeded) {
    for (const utxo of utxos) {
      if (selectedUtxos.some(s => s.tx_hash === utxo.tx_hash && s.output_index === utxo.output_index)) continue
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

  // === INPUTS ===
  const inputs = selectedUtxos.map(utxo => cborArray([
    cborBytes(hexToBytes(utxo.tx_hash)),
    cborUint(utxo.output_index),
  ]))

  // === OUTPUTS ===

  // Output 0: Reference NFT back to platform with UPDATED datum
  const refTokenMap: [number[], number[]][] = [
    [cborBytes(refAssetNameBytes), cborUint(1)],
  ]
  const refMultiAsset: [number[], number[]][] = [
    [cborBytes(policyIdBytes), cborMap(refTokenMap)],
  ]
  const refValue = cborArray([cborUint(minAdaRefOutput), cborMap(refMultiAsset)])
  const datumWrapped = cborTag(24, cborBytes(new Uint8Array(metadataDatumCbor)))
  const datumOption = cborArray([cborUint(1), datumWrapped])
  const refOutput = cborMap([
    [cborUint(0), cborBytes(platformAddressBytes)],
    [cborUint(1), refValue],
    [cborUint(2), datumOption],
  ])

  // Output 1: NEW user token to buyer
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

  // Output 2: Change to platform
  const outputs = [refOutput, userOutput]
  if (change >= 1_000_000) {
    outputs.push(cborArray([
      cborBytes(platformAddressBytes),
      cborUint(change),
    ]))
  }

  // === MINT (key 9) — mint +1 user token for buyer ===
  const mintAssets: [number[], number[]][] = [
    [cborBytes(userAssetNameBytes), cborUint(1)],
  ]
  const mintMap: [number[], number[]][] = [
    [cborBytes(policyIdBytes), cborMap(mintAssets)],
  ]

  // === TX BODY ===
  const txBodyEntries: [number[], number[]][] = [
    [cborUint(0), cborArray(inputs)],
    [cborUint(1), cborArray(outputs)],
    [cborUint(2), cborUint(estimatedFee)],
    [cborUint(3), cborUint(ttl)],
    [cborUint(9), cborMap(mintMap)],
  ]

  return cborMap(txBodyEntries)
}

function buildWitnessSet(
  txBodyHash: Uint8Array, kL: Uint8Array, kR: Uint8Array,
  publicKey: Uint8Array, policyScriptCbor: Uint8Array,
): number[] {
  const signature = bip32Ed25519Sign(txBodyHash, kL, kR, publicKey)
  const vkeyWitness = cborArray([cborBytes(publicKey), cborBytes(signature)])
  const witnessEntries: [number[], number[]][] = [
    [cborUint(0), cborArray([vkeyWitness])],
    [cborUint(1), cborArray([Array.from(policyScriptCbor)])],
  ]
  return cborMap(witnessEntries)
}

// ====================================================================
// Main handler
// ====================================================================

serve(async (req) => {
  try {
    const { queue_id, ticket_id } = await req.json()

    if (!ticket_id && !queue_id) {
      return jsonResponse({ error: 'ticket_id or queue_id required' }, 400)
    }

    // Find queue entry (transfer type)
    let queueEntry: any
    if (queue_id) {
      const { data, error } = await supabase.from('nft_mint_queue').select('*').eq('id', queue_id).single()
      if (error || !data) return jsonResponse({ error: 'Queue entry not found' }, 404)
      queueEntry = data
    } else {
      const { data, error } = await supabase.from('nft_mint_queue').select('*')
        .eq('ticket_id', ticket_id).eq('action', 'transfer').eq('status', 'queued')
        .order('created_at', { ascending: true }).limit(1).single()
      if (error || !data) return jsonResponse({ error: 'No queued transfer for this ticket' }, 404)
      queueEntry = data
    }

    // Mark as transferring
    await supabase.from('nft_mint_queue').update({ status: 'transferring' }).eq('id', queueEntry.id)
    console.log(`[transfer] Starting NFT transfer for ticket ${queueEntry.ticket_id}`)

    // Get ticket + event
    const { data: ticket } = await supabase.from('tickets').select('*, events(*)').eq('id', queueEntry.ticket_id).single()
    if (!ticket) {
      await markFailed(queueEntry.id, 'Ticket not found')
      return jsonResponse({ error: 'Ticket not found' }, 404)
    }
    if (!ticket.nft_minted || !ticket.nft_asset_id || !ticket.nft_policy_id) {
      await markFailed(queueEntry.id, 'Ticket has no minted NFT')
      return jsonResponse({ error: 'Ticket has no minted NFT to transfer' }, 400)
    }
    const event = ticket.events

    // 1. Platform keys
    const keys = getPlatformKeys()
    const paymentKeyHash = blake2b224(keys.publicKey)

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
    console.log(`[transfer] Platform address: ${platformAddress}`)

    // 2. Policy info (use ticket's existing policy)
    const policyScriptCbor = buildPubKeyNativeScript(paymentKeyHash)
    const policyId = bytesToHex(computePolicyId(policyScriptCbor))
    console.log(`[transfer] Policy ID: ${policyId}`)

    // Verify policy matches ticket
    if (policyId !== ticket.nft_policy_id) {
      await markFailed(queueEntry.id, `Policy mismatch: computed ${policyId} vs ticket ${ticket.nft_policy_id}`)
      return jsonResponse({ error: 'Policy ID mismatch' }, 500)
    }

    // 3. Asset names (derived from ticket number, same as original mint)
    const ticketName = `TCKT${ticket.ticket_number.replace(/[^A-Za-z0-9]/g, '')}`
    const nameHex = stringToHex(ticketName)
    const refAssetName = CIP68_REFERENCE_LABEL + nameHex
    const userAssetName = CIP68_USER_TOKEN_LABEL + nameHex
    const fullRefAssetId = policyId + refAssetName
    console.log(`[transfer] Assets: ref=${refAssetName}, user=${userAssetName}`)

    // 4. Build updated CIP-68 datum with new owner info
    const textAsBytes = (s: string) => cborBytes(new TextEncoder().encode(s))
    const metadataFields: [number[], number[]][] = [
      [textAsBytes('name'), textAsBytes(`Tickety #${ticket.ticket_number}`)],
      [textAsBytes('event'), textAsBytes(event.title)],
      [textAsBytes('event_id'), textAsBytes(event.id)],
      [textAsBytes('ticket_number'), textAsBytes(ticket.ticket_number)],
      [textAsBytes('ticket_id'), textAsBytes(ticket.id)],
      [textAsBytes('owner'), textAsBytes(queueEntry.buyer_address)],
    ]
    if (event.date) metadataFields.push([textAsBytes('event_date'), textAsBytes(event.date)])
    if (event.venue) metadataFields.push([textAsBytes('venue'), textAsBytes(event.venue)])

    const metadataDatumCbor = [
      0xd8, 0x79, // tag(121) = Constructor 0
      ...cborArray([
        cborMap(metadataFields),
        cborUint(1),
        cborBytes(new Uint8Array(0)),
      ]),
    ]

    // 5. Fetch UTxOs, protocol params, latest block
    const [allUtxos, protocolParams, latestBlock] = await Promise.all([
      blockfrostGet(`/addresses/${platformAddress}/utxos`).catch((err: Error) => {
        console.error(`[transfer] UTxO fetch failed: ${err.message}`)
        return null
      }),
      blockfrostGet('/epochs/latest/parameters'),
      blockfrostGet('/blocks/latest'),
    ])

    if (!allUtxos || (Array.isArray(allUtxos) && allUtxos.length === 0)) {
      await markFailed(queueEntry.id, 'No UTxOs at platform address')
      return jsonResponse({ error: 'No UTxOs at platform address' }, 503)
    }

    // 6. Find the reference NFT UTxO
    const refUtxo = allUtxos.find((u: any) =>
      u.amount.some((a: any) => a.unit === fullRefAssetId)
    )
    if (!refUtxo) {
      await markFailed(queueEntry.id, `Reference NFT UTxO not found for ${fullRefAssetId}`)
      return jsonResponse({ error: 'Reference NFT not found at platform address' }, 404)
    }
    console.log(`[transfer] Found reference NFT at ${refUtxo.tx_hash}#${refUtxo.output_index}`)

    // 7. Build transfer transaction
    const buyerAddressHex = bech32ToHex(queueEntry.buyer_address)

    const txBody = buildTransferTx({
      utxos: allUtxos,
      refUtxo,
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

    // 8. Hash and sign
    const txBodyBytes = new Uint8Array(txBody)
    const txBodyHash = blake2b256(txBodyBytes)
    console.log(`[transfer] Tx body hash: ${bytesToHex(txBodyHash)} (${txBodyBytes.length} bytes)`)

    const witnessSet = buildWitnessSet(txBodyHash, keys.kL, keys.kR, keys.publicKey, policyScriptCbor)

    const signedTx = cborArray([txBody, witnessSet, [0xf5], [0xf6]])
    const signedTxHex = bytesToHex(new Uint8Array(signedTx))
    console.log(`[transfer] Submitting tx (${signedTxHex.length / 2} bytes)...`)

    // 9. Submit
    const txHash = await blockfrostSubmitTx(signedTxHex)
    console.log(`[transfer] Tx submitted: ${txHash}`)

    // 10. Update DB
    await supabase.from('nft_mint_queue').update({
      status: 'transferred',
      tx_hash: txHash,
      policy_id: policyId,
      user_asset_id: policyId + userAssetName,
    }).eq('id', queueEntry.id)

    // Update ticket's transfer tx hash
    await supabase.from('tickets').update({
      nft_transfer_tx_hash: txHash,
    }).eq('id', queueEntry.ticket_id)

    return jsonResponse({
      success: true,
      tx_hash: txHash,
      policy_id: policyId,
      user_asset_id: policyId + userAssetName,
    })

  } catch (err) {
    console.error('[transfer] Error:', err)
    try {
      const { queue_id } = await req.clone().json().catch(() => ({}))
      if (queue_id) await markFailed(queue_id, err.message)
    } catch (_) {}
    return jsonResponse({ error: err.message }, 500)
  }
})

const MAX_DELAY_MS = 86_400_000 // 24 hours

async function markFailed(queueId: string, errorMessage: string) {
  const { data } = await supabase.from('nft_mint_queue').select('retry_count').eq('id', queueId).single()
  const retryCount = (data?.retry_count || 0) + 1

  const delayMs = Math.min(10_000 * Math.pow(3, retryCount - 1), MAX_DELAY_MS)

  await supabase.from('nft_mint_queue').update({
    status: 'queued',
    error_message: `Retry #${retryCount}: ${errorMessage}`,
    retry_count: retryCount,
  }).eq('id', queueId)

  console.log(`[transfer] Auto-retry #${retryCount} for ${queueId} in ${Math.round(delayMs / 1000)}s`)

  setTimeout(() => {
    fetch(`${supabaseUrl}/functions/v1/transfer-ticket-nft`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${supabaseServiceKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ queue_id: queueId }),
    }).catch(err => console.error(`[transfer] Retry invocation failed: ${err}`))
  }, delayMs)
}

function jsonResponse(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}
