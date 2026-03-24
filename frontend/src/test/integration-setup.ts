import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { GRPC_URLS } from '@/config/network';
import { TESTNET_OBJECTS, ADMIN_CAPS } from '@/config/objects';
import { PACKAGE_ID, TYPE } from '@/config/contracts';

// ─── Keypair ───────────────────────────────────────────────
function loadTestKeypair(): Ed25519Keypair {
  const secret = process.env.TEST_SECRET_KEY;
  if (!secret) {
    throw new Error(
      'TEST_SECRET_KEY not set. Copy .env.test.local.example to .env.test.local and add your key.',
    );
  }
  // Accept both bech32 (suiprivkey1...) and base64 raw 32-byte formats
  if (secret.startsWith('suiprivkey')) {
    return Ed25519Keypair.fromSecretKey(secret);
  }
  return Ed25519Keypair.fromSecretKey(Buffer.from(secret, 'base64'));
}

// ─── Shared instances ──────────────────────────────────────
export const testKeypair = loadTestKeypair();
export const testAddress = testKeypair.toSuiAddress();
export const testClient = new SuiGrpcClient({
  baseUrl: GRPC_URLS.testnet,
  network: 'testnet',
});

// Re-export for convenience
export { TESTNET_OBJECTS, ADMIN_CAPS, PACKAGE_ID, TYPE };

// ─── Transaction helpers ───────────────────────────────────
export async function signAndExec(tx: Transaction) {
  const result = await testClient.signAndExecuteTransaction({
    signer: testKeypair,
    transaction: tx,
    include: { objectTypes: true },
  });

  if (result.$kind === 'FailedTransaction') {
    const status = result.FailedTransaction.status;
    throw new Error(`Transaction failed: ${JSON.stringify(status)}`);
  }

  const txData = result.Transaction!;
  await testClient.waitForTransaction({ digest: txData.digest });
  return { digest: txData.digest, objectTypes: txData.objectTypes ?? {} };
}

export function findCreatedId(
  result: { objectTypes: Record<string, string> },
  typeSubstr: string,
): string {
  for (const [id, type] of Object.entries(result.objectTypes)) {
    if (type.includes(typeSubstr)) return id;
  }
  throw new Error(`Object containing "${typeSubstr}" not found in tx output`);
}

// ─── Query helpers ─────────────────────────────────────────
export async function queryObject(objectId: string) {
  const res = await testClient.getObject({
    objectId,
    include: { json: true },
  });
  // res.object is always defined (SDK throws if object doesn't exist)
  return res.object;
}

/** Returns first page of owned objects matching type. Does not paginate. */
export async function queryOwnedObjects(type: string) {
  const res = await testClient.listOwnedObjects({
    owner: testAddress,
    type,
    limit: 50,
  });
  return res.objects;
}
