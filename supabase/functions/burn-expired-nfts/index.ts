import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import { ed25519 } from 'https://esm.sh/@noble/curves@1.3.0/ed25519'
import { sha512 } from 'https://esm.sh/@noble/hashes@1.3.3/sha512'
import { sha256 } from 'https://esm.sh/@noble/hashes@1.3.3/sha256'
import { blake2b as _blake2b } from 'https://esm.sh/@noble/hashes@1.3.3/blake2b'
import { hmac } from 'https://esm.sh/@noble/hashes@1.3.3/hmac'
import { pbkdf2 as _pbkdf2 } from 'https://esm.sh/@noble/hashes@1.3.3/pbkdf2'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const blockfrostProjectId = Deno.env.get('BLOCKFROST_PROJECT_ID') || 'previewVA5jY9V686T1apRZItmlqZUf5jOEpNqB'
const platformSigningKeyHex = Deno.env.get('PLATFORM_CARDANO_SIGNING_KEY') || ''
const platformVerifyKeyHex = Deno.env.get('PLATFORM_CARDANO_VERIFY_KEY') || ''

const supabase = createClient(supabaseUrl, supabaseServiceKey)
const BLOCKFROST_BASE = 'https://cardano-preview.blockfrost.io/api/v0'

const CIP68_REFERENCE_LABEL = '000643b0'
const CIP68_USER_TOKEN_LABEL = '000de140'

const ED25519_L = 2n ** 252n + 27742317777372353535851937790883648493n
const MAX_RETRIES = 5
const BATCH_SIZE = 10 // Process up to 10 burns per invocation

// ====================================================================
// BIP32-Ed25519 key derivation from mnemonic (CIP-1852)
// ====================================================================

// BIP39 mnemonic → seed entropy (no passphrase)
function mnemonicToEntropy(mnemonic: string): Uint8Array {
  const passphrase = ''
  const mnemonicBytes = new TextEncoder().encode(mnemonic.normalize('NFKD'))
  const salt = new TextEncoder().encode(('mnemonic' + passphrase).normalize('NFKD'))
  return _pbkdf2(sha512, mnemonicBytes, salt, { c: 2048, dkLen: 64 })
}

// Icarus-V2 master key derivation (used by Cardano/Yoroi/Daedalus)
// PBKDF2-HMAC-SHA512 with the password being the BIP39 entropy
function deriveIcarusMasterKey(mnemonic: string): Uint8Array {
  const entropy = mnemonicToEntropy(mnemonic)
  // Icarus derivation: PBKDF2-HMAC-SHA512(password=entropy, salt="", iterations=4096, dkLen=96)
  // Actually the Icarus V2 method uses passphrase-based derivation
  // But Cardano standard (CIP-3 Icarus) uses a simpler approach:
  // master_key = PBKDF2-HMAC-SHA512(password=entropy, salt="", iterations=4096, dkLen=96)
  const emptyPassword = new Uint8Array(0)
  const masterKey = _pbkdf2(sha512, emptyPassword, entropy, { c: 4096, dkLen: 96 })

  // Clamp the private key (first 32 bytes = kL)
  masterKey[0] &= 0xf8  // Clear bottom 3 bits
  masterKey[31] &= 0x1f  // Clear top 3 bits
  masterKey[31] |= 0x40  // Set second-to-top bit

  return masterKey // 96 bytes: kL(32) + kR(32) + chainCode(32)
}

// BIP32-Ed25519 child key derivation (hardened)
function deriveChildHardened(parentKey: Uint8Array, index: number): Uint8Array {
  const kL = parentKey.slice(0, 32)
  const kR = parentKey.slice(32, 64)
  const cc = parentKey.slice(64, 96)

  // Hardened index: 0x80000000 + index
  const indexBuf = new Uint8Array(4)
  const idx = (0x80000000 + index) >>> 0
  indexBuf[0] = idx & 0xff
  indexBuf[1] = (idx >> 8) & 0xff
  indexBuf[2] = (idx >> 16) & 0xff
  indexBuf[3] = (idx >> 24) & 0xff

  // Z = HMAC-SHA512(cc, 0x00 || kL || kR || index_LE)
  const zInput = new Uint8Array(1 + 64 + 4)
  zInput[0] = 0x00
  zInput.set(kL, 1)
  zInput.set(kR, 33)
  zInput.set(indexBuf, 65)
  const Z = hmac(sha512, cc, zInput)

  // c = HMAC-SHA512(cc, 0x01 || kL || kR || index_LE)
  const cInput = new Uint8Array(1 + 64 + 4)
  cInput[0] = 0x01
  cInput.set(kL, 1)
  cInput.set(kR, 33)
  cInput.set(indexBuf, 65)
  const C = hmac(sha512, cc, cInput)

  const zL = Z.slice(0, 28) // Only first 28 bytes of left half
  const zR = Z.slice(32, 64)
  const childCC = C.slice(32, 64)

  // child_kL = zL * 8 + kL (mod 2^256) — but we add as little-endian integers
  const childKL = addScalars(scalarMul8(zL), kL)

  // Clamp child kL
  childKL[0] &= 0xf8
  childKL[31] &= 0x1f
  childKL[31] |= 0x40

  // child_kR = zR + kR (mod 2^256)
  const childKR = addBytes32(zR, kR)

  const result = new Uint8Array(96)
  result.set(childKL, 0)
  result.set(childKR, 32)
  result.set(childCC, 64)
  return result
}

// BIP32-Ed25519 child key derivation (soft/normal)
function deriveChildNormal(parentKey: Uint8Array, parentPub: Uint8Array, index: number): Uint8Array {
  const kL = parentKey.slice(0, 32)
  const kR = parentKey.slice(32, 64)
  const cc = parentKey.slice(64, 96)

  const indexBuf = new Uint8Array(4)
  indexBuf[0] = index & 0xff
  indexBuf[1] = (index >> 8) & 0xff
  indexBuf[2] = (index >> 16) & 0xff
  indexBuf[3] = (index >> 24) & 0xff

  // Z = HMAC-SHA512(cc, 0x02 || pubKey || index_LE)
  const zInput = new Uint8Array(1 + 32 + 4)
  zInput[0] = 0x02
  zInput.set(parentPub, 1)
  zInput.set(indexBuf, 33)
  const Z = hmac(sha512, cc, zInput)

  // c = HMAC-SHA512(cc, 0x03 || pubKey || index_LE)
  const cInput = new Uint8Array(1 + 32 + 4)
  cInput[0] = 0x03
  cInput.set(parentPub, 1)
  cInput.set(indexBuf, 33)
  const C = hmac(sha512, cc, cInput)

  const zL = Z.slice(0, 28)
  const zR = Z.slice(32, 64)
  const childCC = C.slice(32, 64)

  const childKL = addScalars(scalarMul8(zL), kL)
  childKL[0] &= 0xf8
  childKL[31] &= 0x1f
  childKL[31] |= 0x40

  const childKR = addBytes32(zR, kR)

  const result = new Uint8Array(96)
  result.set(childKL, 0)
  result.set(childKR, 32)
  result.set(childCC, 64)
  return result
}

// Derive CIP-1852 payment signing key: m/1852'/1815'/0'/0/0
function derivePaymentKeyFromMnemonic(mnemonic: string): { kL: Uint8Array; kR: Uint8Array; publicKey: Uint8Array } {
  const masterKey = deriveIcarusMasterKey(mnemonic)

  // Hardened derivation: purpose / coin_type / account
  const purposeKey = deriveChildHardened(masterKey, 1852)   // m/1852'
  const coinKey = deriveChildHardened(purposeKey, 1815)     // m/1852'/1815'
  const accountKey = deriveChildHardened(coinKey, 0)        // m/1852'/1815'/0'

  // Soft derivation: role / index
  const accountPub = publicKeyFromExtended(accountKey)
  const roleKey = deriveChildNormal(accountKey, accountPub, 0)  // m/.../0'/0
  const rolePub = publicKeyFromExtended(roleKey)
  const addrKey = deriveChildNormal(roleKey, rolePub, 0)        // m/.../0'/0/0

  const kL = addrKey.slice(0, 32)
  const kR = addrKey.slice(32, 64)
  const publicKey = publicKeyFromExtended(addrKey)

  return { kL, kR, publicKey }
}

function publicKeyFromExtended(extKey: Uint8Array): Uint8Array {
  const kL = extKey.slice(0, 32)
  const scalar = bytesToBigIntLE(kL)
  const point = ed25519.ExtendedPoint.BASE.multiply(scalar)
  return point.toRawBytes()
}

// Little-endian 28-byte value * 8, returned as 32 bytes
function scalarMul8(bytes28: Uint8Array): Uint8Array {
  const result = new Uint8Array(32)
  let carry = 0
  for (let i = 0; i < 28; i++) {
    const v = bytes28[i] * 8 + carry
    result[i] = v & 0xff
    carry = v >> 8
  }
  for (let i = 28; i < 32; i++) {
    result[i] = carry & 0xff
    carry >>= 8
  }
  return result
}

// Add two 32-byte little-endian integers (mod 2^256)
function addScalars(a: Uint8Array, b: Uint8Array): Uint8Array {
  const result = new Uint8Array(32)
  let carry = 0
  for (let i = 0; i < 32; i++) {
    const s = a[i] + b[i] + carry
    result[i] = s & 0xff
    carry = s >> 8
  }
  return result
}

function addBytes32(a: Uint8Array, b: Uint8Array): Uint8Array {
  return addScalars(a, b)
}

// ====================================================================
// Platform key helpers (same as mint/transfer)
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

// BIP32-Ed25519 signing (same as mint/transfer)
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
// Blake2b / Bech32 / Hex / CBOR (same as mint/transfer)
// ====================================================================

function blake2b224(input: Uint8Array): Uint8Array { return _blake2b(input, { dkLen: 28 }) }
function blake2b256(input: Uint8Array): Uint8Array { return _blake2b(input, { dkLen: 32 }) }

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

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < hex.length; i += 2) bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16)
  return bytes
}
function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('')
}
function stringToHex(s: string): string { return bytesToHex(new TextEncoder().encode(s)) }

function cborUint(value: number): number[] {
  if (value < 24) return [value]
  if (value < 256) return [24, value]
  if (value < 65536) return [25, value >> 8, value & 0xff]
  if (value < 4294967296) return [26, (value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff]
  const hi = Math.floor(value / 4294967296); const lo = value >>> 0
  return [27, (hi >>> 24) & 0xff, (hi >>> 16) & 0xff, (hi >>> 8) & 0xff, hi & 0xff,
    (lo >>> 24) & 0xff, (lo >>> 16) & 0xff, (lo >>> 8) & 0xff, lo & 0xff]
}

// CBOR negative integer: major type 1
function cborNegInt(value: number): number[] {
  // Encodes -1-value, so for -1 pass value=0, for -2 pass value=1
  const mt = 1 << 5
  if (value < 24) return [mt | value]
  if (value < 256) return [mt | 24, value]
  if (value < 65536) return [mt | 25, value >> 8, value & 0xff]
  return [mt | 26, (value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff]
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
// Build burn transaction
// ====================================================================
// Burns both the reference NFT (at platform address) and user token (at buyer address).
// All reclaimed ADA goes to platform address.
// Requires TWO signatures: platform key (policy + ref UTxO) and buyer key (user token UTxO).

function buildBurnTx(params: {
  platformUtxos: any[]       // All UTxOs at platform address
  buyerUtxos: any[]          // All UTxOs at buyer address
  refUtxo: any               // Specific UTxO holding reference NFT
  userTokenUtxo: any         // Specific UTxO holding user token
  platformAddressBytes: Uint8Array
  policyId: string
  policyScriptCbor: Uint8Array
  refAssetName: string
  userAssetName: string
  protocolParams: any
  currentSlot: number
}): number[] {
  const {
    platformUtxos, buyerUtxos, refUtxo, userTokenUtxo,
    platformAddressBytes, policyId, policyScriptCbor,
    refAssetName, userAssetName, protocolParams, currentSlot,
  } = params

  const minFeeA = parseInt(protocolParams.min_fee_a)
  const minFeeB = parseInt(protocolParams.min_fee_b)
  const ttl = currentSlot + 7200

  // Fee estimate: burn tx with 2 witnesses is ~1000 bytes
  const estimatedFee = (1100 * minFeeA) + minFeeB

  const policyIdBytes = hexToBytes(policyId)
  const refAssetNameBytes = hexToBytes(refAssetName)
  const userAssetNameBytes = hexToBytes(userAssetName)

  // Inputs: reference NFT UTxO + user token UTxO
  const selectedUtxos = [refUtxo, userTokenUtxo]
  let totalInput = 0

  for (const utxo of selectedUtxos) {
    totalInput += parseInt(utxo.amount.find((a: any) => a.unit === 'lovelace')?.quantity || '0')
  }

  // We need at least fee + min output (~1 ADA for change)
  const minChange = 1_000_000
  if (totalInput < estimatedFee + minChange) {
    // Need more ADA from platform to cover fees — add ADA-only UTxOs
    const extraUtxos = platformUtxos.filter((u: any) =>
      !(u.tx_hash === refUtxo.tx_hash && u.output_index === refUtxo.output_index)
    ).filter((u: any) => u.amount.length === 1 && u.amount[0].unit === 'lovelace')

    for (const utxo of extraUtxos) {
      selectedUtxos.push(utxo)
      totalInput += parseInt(utxo.amount.find((a: any) => a.unit === 'lovelace')?.quantity || '0')
      if (totalInput >= estimatedFee + minChange) break
    }
  }

  if (totalInput < estimatedFee + minChange) {
    throw new Error(`Insufficient ADA for burn. Need ${estimatedFee + minChange}, have ${totalInput}`)
  }

  const change = totalInput - estimatedFee

  // === INPUTS ===
  const inputs = selectedUtxos.map(utxo => cborArray([
    cborBytes(hexToBytes(utxo.tx_hash)),
    cborUint(utxo.output_index),
  ]))

  // === OUTPUTS ===
  // Single output: all change goes to platform address (reclaimed ADA)
  const outputs = [
    cborArray([
      cborBytes(platformAddressBytes),
      cborUint(change),
    ]),
  ]

  // === MINT (key 9) — burn both tokens: -1 each ===
  // CBOR negative: -1 is encoded as major type 1, value 0
  const mintAssets: [number[], number[]][] = [
    [cborBytes(refAssetNameBytes), cborNegInt(0)],    // -1 (burn reference NFT)
    [cborBytes(userAssetNameBytes), cborNegInt(0)],   // -1 (burn user token)
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

// Build witness set with TWO signatures: platform + buyer
function buildDualWitnessSet(
  txBodyHash: Uint8Array,
  platformKL: Uint8Array, platformKR: Uint8Array, platformPub: Uint8Array,
  buyerKL: Uint8Array, buyerKR: Uint8Array, buyerPub: Uint8Array,
  policyScriptCbor: Uint8Array,
): number[] {
  const platSig = bip32Ed25519Sign(txBodyHash, platformKL, platformKR, platformPub)
  const buyerSig = bip32Ed25519Sign(txBodyHash, buyerKL, buyerKR, buyerPub)

  const platWitness = cborArray([cborBytes(platformPub), cborBytes(platSig)])
  const buyerWitness = cborArray([cborBytes(buyerPub), cborBytes(buyerSig)])

  const witnessEntries: [number[], number[]][] = [
    [cborUint(0), cborArray([platWitness, buyerWitness])],       // vkey witnesses
    [cborUint(1), cborArray([Array.from(policyScriptCbor)])],    // native scripts
  ]

  return cborMap(witnessEntries)
}

// ====================================================================
// Process a single burn
// ====================================================================

async function processBurn(queueEntry: any): Promise<{ success: boolean; txHash?: string; error?: string }> {
  const queueId = queueEntry.id

  try {
    // Mark as burning
    await supabase.from('nft_mint_queue').update({ status: 'burning' }).eq('id', queueId)
    console.log(`[burn] Processing burn for ticket ${queueEntry.ticket_id}`)

    // Get ticket + event
    const { data: ticket } = await supabase.from('tickets').select('*, events(*)').eq('id', queueEntry.ticket_id).single()
    if (!ticket) {
      await markFailed(queueId, 'Ticket not found')
      return { success: false, error: 'Ticket not found' }
    }
    if (!ticket.nft_minted || !ticket.nft_policy_id) {
      await markFailed(queueId, 'Ticket has no minted NFT')
      return { success: false, error: 'No NFT to burn' }
    }

    // Get buyer's mnemonic from user_wallets
    const { data: userWallet } = await supabase
      .from('user_wallets')
      .select('mnemonic, cardano_address')
      .eq('user_id', ticket.user_id)
      .single()

    if (!userWallet?.mnemonic) {
      // No wallet = no user token to burn. Mark as burned anyway (token is orphaned).
      await supabase.from('nft_mint_queue').update({
        status: 'burned',
        error_message: 'No user wallet — token orphaned, ref NFT burn only',
      }).eq('id', queueId)
      // We could still burn the reference NFT, but skip for now
      console.log(`[burn] Skipping ${queueId}: no user wallet`)
      return { success: true, txHash: 'skipped_no_wallet' }
    }

    // 1. Derive keys
    const platformKeys = getPlatformKeys()
    const platformKeyHash = blake2b224(platformKeys.publicKey)

    // Derive buyer's payment key from mnemonic
    const buyerKeys = derivePaymentKeyFromMnemonic(userWallet.mnemonic)
    console.log(`[burn] Buyer pubkey: ${bytesToHex(buyerKeys.publicKey).substring(0, 16)}...`)

    // 2. Platform address
    const { data: configRows } = await supabase.from('platform_cardano_config').select('key, value')
    const configMap: Record<string, string> = {}
    for (const row of configRows ?? []) configMap[row.key] = row.value
    const platformAddress = configMap.minting_address
    if (!platformAddress) {
      await markFailed(queueId, 'No minting_address configured')
      return { success: false, error: 'No platform address' }
    }
    const platformAddressBytes = hexToBytes(bech32ToHex(platformAddress))

    // 3. Policy
    const policyScriptCbor = buildPubKeyNativeScript(platformKeyHash)
    const policyId = bytesToHex(computePolicyId(policyScriptCbor))

    if (policyId !== ticket.nft_policy_id) {
      await markFailed(queueId, `Policy mismatch: ${policyId} vs ${ticket.nft_policy_id}`)
      return { success: false, error: 'Policy mismatch' }
    }

    // 4. Asset names
    const ticketName = `TCKT${ticket.ticket_number.replace(/[^A-Za-z0-9]/g, '')}`
    const nameHex = stringToHex(ticketName)
    const refAssetName = CIP68_REFERENCE_LABEL + nameHex
    const userAssetName = CIP68_USER_TOKEN_LABEL + nameHex
    const fullRefAssetId = policyId + refAssetName
    const fullUserAssetId = policyId + userAssetName

    // 5. Fetch UTxOs from both addresses + protocol params
    const buyerAddress = userWallet.cardano_address
    const [platformUtxos, buyerUtxos, protocolParams, latestBlock] = await Promise.all([
      blockfrostGet(`/addresses/${platformAddress}/utxos`).catch(() => null),
      blockfrostGet(`/addresses/${buyerAddress}/utxos`).catch(() => null),
      blockfrostGet('/epochs/latest/parameters'),
      blockfrostGet('/blocks/latest'),
    ])

    if (!platformUtxos || !Array.isArray(platformUtxos)) {
      await markFailed(queueId, 'Failed to fetch platform UTxOs')
      return { success: false, error: 'No platform UTxOs' }
    }

    // Find reference NFT UTxO at platform address
    const refUtxo = platformUtxos.find((u: any) =>
      u.amount.some((a: any) => a.unit === fullRefAssetId)
    )
    if (!refUtxo) {
      // Reference NFT not found — may already be burned
      await supabase.from('nft_mint_queue').update({
        status: 'burned',
        error_message: 'Reference NFT not found at platform — may be already burned',
      }).eq('id', queueId)
      await supabase.from('tickets').update({
        nft_burned: true, nft_burned_at: new Date().toISOString(),
      }).eq('id', ticket.id)
      return { success: true, txHash: 'ref_already_gone' }
    }

    // Find user token UTxO at buyer address
    if (!buyerUtxos || !Array.isArray(buyerUtxos)) {
      await markFailed(queueId, 'Failed to fetch buyer UTxOs')
      return { success: false, error: 'No buyer UTxOs' }
    }

    const userTokenUtxo = buyerUtxos.find((u: any) =>
      u.amount.some((a: any) => a.unit === fullUserAssetId)
    )
    if (!userTokenUtxo) {
      // User token not at expected address — may have been sent elsewhere
      // Still burn the reference NFT
      console.log(`[burn] User token not found at buyer address. Burning ref NFT only.`)
      // Build ref-only burn (single signature)
      const txBody = buildRefOnlyBurnTx({
        platformUtxos,
        refUtxo,
        platformAddressBytes,
        policyId,
        policyScriptCbor,
        refAssetName,
        protocolParams,
        currentSlot: latestBlock.slot,
      })

      const txBodyBytes = new Uint8Array(txBody)
      const txBodyHash = blake2b256(txBodyBytes)
      const witnessSet = buildSingleWitnessSet(txBodyHash, platformKeys.kL, platformKeys.kR, platformKeys.publicKey, policyScriptCbor)
      const signedTx = cborArray([txBody, witnessSet, [0xf5], [0xf6]])
      const signedTxHex = bytesToHex(new Uint8Array(signedTx))

      const txHash = await blockfrostSubmitTx(signedTxHex)
      console.log(`[burn] Ref-only burn tx: ${txHash}`)

      await supabase.from('nft_mint_queue').update({
        status: 'burned', tx_hash: txHash,
        error_message: 'User token not at expected address — ref NFT burned only',
      }).eq('id', queueId)
      await supabase.from('tickets').update({
        nft_burned: true, nft_burned_at: new Date().toISOString(), nft_burn_tx_hash: txHash,
      }).eq('id', ticket.id)
      return { success: true, txHash }
    }

    // 6. Build full burn transaction (both tokens)
    console.log(`[burn] Building burn tx: ref=${refUtxo.tx_hash}#${refUtxo.output_index}, user=${userTokenUtxo.tx_hash}#${userTokenUtxo.output_index}`)

    const txBody = buildBurnTx({
      platformUtxos,
      buyerUtxos,
      refUtxo,
      userTokenUtxo,
      platformAddressBytes,
      policyId,
      policyScriptCbor,
      refAssetName,
      userAssetName,
      protocolParams,
      currentSlot: latestBlock.slot,
    })

    // 7. Hash and sign with both keys
    const txBodyBytes = new Uint8Array(txBody)
    const txBodyHash = blake2b256(txBodyBytes)
    console.log(`[burn] Tx body hash: ${bytesToHex(txBodyHash)} (${txBodyBytes.length} bytes)`)

    const witnessSet = buildDualWitnessSet(
      txBodyHash,
      platformKeys.kL, platformKeys.kR, platformKeys.publicKey,
      buyerKeys.kL, buyerKeys.kR, buyerKeys.publicKey,
      policyScriptCbor,
    )

    const signedTx = cborArray([txBody, witnessSet, [0xf5], [0xf6]])
    const signedTxHex = bytesToHex(new Uint8Array(signedTx))
    console.log(`[burn] Submitting burn tx (${signedTxHex.length / 2} bytes)...`)

    // 8. Submit
    const txHash = await blockfrostSubmitTx(signedTxHex)
    console.log(`[burn] Burn tx submitted: ${txHash}`)

    // 9. Update DB
    await supabase.from('nft_mint_queue').update({
      status: 'burned', tx_hash: txHash,
    }).eq('id', queueId)

    await supabase.from('tickets').update({
      nft_burned: true,
      nft_burned_at: new Date().toISOString(),
      nft_burn_tx_hash: txHash,
    }).eq('id', ticket.id)

    return { success: true, txHash }

  } catch (err) {
    console.error(`[burn] Error for ${queueId}:`, err)
    await markFailed(queueId, err.message)
    return { success: false, error: err.message }
  }
}

// Burn only the reference NFT (when user token is missing)
function buildRefOnlyBurnTx(params: {
  platformUtxos: any[]
  refUtxo: any
  platformAddressBytes: Uint8Array
  policyId: string
  policyScriptCbor: Uint8Array
  refAssetName: string
  protocolParams: any
  currentSlot: number
}): number[] {
  const {
    platformUtxos, refUtxo, platformAddressBytes, policyId,
    policyScriptCbor, refAssetName, protocolParams, currentSlot,
  } = params

  const minFeeA = parseInt(protocolParams.min_fee_a)
  const minFeeB = parseInt(protocolParams.min_fee_b)
  const ttl = currentSlot + 7200
  const estimatedFee = (900 * minFeeA) + minFeeB

  const selectedUtxos = [refUtxo]
  let totalInput = parseInt(refUtxo.amount.find((a: any) => a.unit === 'lovelace')?.quantity || '0')

  if (totalInput < estimatedFee + 1_000_000) {
    const extras = platformUtxos.filter((u: any) =>
      !(u.tx_hash === refUtxo.tx_hash && u.output_index === refUtxo.output_index)
    ).filter((u: any) => u.amount.length === 1 && u.amount[0].unit === 'lovelace')
    for (const utxo of extras) {
      selectedUtxos.push(utxo)
      totalInput += parseInt(utxo.amount.find((a: any) => a.unit === 'lovelace')?.quantity || '0')
      if (totalInput >= estimatedFee + 1_000_000) break
    }
  }

  const change = totalInput - estimatedFee
  const policyIdBytes = hexToBytes(policyId)
  const refAssetNameBytes = hexToBytes(refAssetName)

  const inputs = selectedUtxos.map(utxo => cborArray([
    cborBytes(hexToBytes(utxo.tx_hash)),
    cborUint(utxo.output_index),
  ]))

  const outputs = [cborArray([cborBytes(platformAddressBytes), cborUint(change)])]

  const mintAssets: [number[], number[]][] = [
    [cborBytes(refAssetNameBytes), cborNegInt(0)],
  ]
  const mintMap: [number[], number[]][] = [
    [cborBytes(policyIdBytes), cborMap(mintAssets)],
  ]

  return cborMap([
    [cborUint(0), cborArray(inputs)],
    [cborUint(1), cborArray(outputs)],
    [cborUint(2), cborUint(estimatedFee)],
    [cborUint(3), cborUint(ttl)],
    [cborUint(9), cborMap(mintMap)],
  ])
}

function buildSingleWitnessSet(
  txBodyHash: Uint8Array, kL: Uint8Array, kR: Uint8Array,
  publicKey: Uint8Array, policyScriptCbor: Uint8Array,
): number[] {
  const signature = bip32Ed25519Sign(txBodyHash, kL, kR, publicKey)
  const vkeyWitness = cborArray([cborBytes(publicKey), cborBytes(signature)])
  return cborMap([
    [cborUint(0), cborArray([vkeyWitness])],
    [cborUint(1), cborArray([Array.from(policyScriptCbor)])],
  ])
}

// ====================================================================
// Retry logic
// ====================================================================

async function markFailed(queueId: string, errorMessage: string) {
  const { data } = await supabase.from('nft_mint_queue').select('retry_count').eq('id', queueId).single()
  const retryCount = (data?.retry_count || 0) + 1

  if (retryCount > MAX_RETRIES) {
    await supabase.from('nft_mint_queue').update({
      status: 'failed',
      error_message: `Gave up after ${retryCount} retries: ${errorMessage}`,
      retry_count: retryCount,
    }).eq('id', queueId)
    console.error(`[burn] Permanently failed ${queueId} after ${retryCount} retries`)
    return
  }

  await supabase.from('nft_mint_queue').update({
    status: 'queued',
    error_message: `Retry #${retryCount}: ${errorMessage}`,
    retry_count: retryCount,
  }).eq('id', queueId)
  console.log(`[burn] Reset ${queueId} to queued (retry #${retryCount})`)
}

// ====================================================================
// Main handler
// ====================================================================

serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}))
    const { queue_id, enqueue } = body

    // Step 1: Optionally enqueue expired NFTs first (called by cron)
    if (enqueue) {
      const { data: enqueueCount, error: enqueueErr } = await supabase.rpc('enqueue_expired_nft_burns', { grace_days: 60 })
      if (enqueueErr) {
        console.error('[burn] Enqueue RPC error:', enqueueErr)
      } else {
        console.log(`[burn] Enqueued ${enqueueCount ?? 0} new burn(s)`)
      }
    }

    let entries: any[] = []

    if (queue_id) {
      // Process a specific queue entry
      const { data, error } = await supabase.from('nft_mint_queue').select('*')
        .eq('id', queue_id).single()
      if (error || !data) return jsonResponse({ error: 'Queue entry not found' }, 404)
      entries = [data]
    } else {
      // Batch mode: pick up queued burn entries
      const { data, error } = await supabase.from('nft_mint_queue').select('*')
        .eq('action', 'burn').eq('status', 'queued')
        .order('created_at', { ascending: true })
        .limit(BATCH_SIZE)
      if (error) return jsonResponse({ error: error.message }, 500)
      entries = data || []
    }

    if (entries.length === 0) {
      return jsonResponse({ message: 'No burns to process', burned: 0 })
    }

    console.log(`[burn] Processing ${entries.length} burn(s)`)

    const results = []
    for (const entry of entries) {
      const result = await processBurn(entry)
      results.push({ queue_id: entry.id, ticket_id: entry.ticket_id, ...result })
      // Small delay between burns to avoid Blockfrost rate limits
      if (entries.length > 1) {
        await new Promise(resolve => setTimeout(resolve, 2000))
      }
    }

    const burned = results.filter(r => r.success).length
    const failed = results.filter(r => !r.success).length

    // If there are more queued burns, fire-and-forget self-invoke for next batch
    if (entries.length === BATCH_SIZE) {
      fetch(`${supabaseUrl}/functions/v1/burn-expired-nfts`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${supabaseServiceKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({}),
      }).catch(err => console.error(`[burn] Next batch invocation failed: ${err}`))
    }

    return jsonResponse({ burned, failed, results })

  } catch (err) {
    console.error('[burn] Error:', err)
    return jsonResponse({ error: err.message }, 500)
  }
})

function jsonResponse(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}
