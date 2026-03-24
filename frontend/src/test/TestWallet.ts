import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import type {
  IdentifierArray,
  IdentifierString,
  StandardConnectFeature,
  StandardConnectMethod,
  StandardEventsFeature,
  StandardEventsOnMethod,
  SuiFeatures,
  SuiSignAndExecuteTransactionMethod,
  SuiSignPersonalMessageMethod,
  SuiSignTransactionMethod,
} from '@mysten/wallet-standard';
import {
  getWallets,
  ReadonlyWalletAccount,
  StandardConnect,
  StandardEvents,
  SuiSignAndExecuteTransaction,
  SuiSignPersonalMessage,
  SuiSignTransaction,
} from '@mysten/wallet-standard';
import type { Wallet } from '@mysten/wallet-standard';
import { toBase64 } from '@mysten/utils';
import type { ClientWithCoreApi } from '@mysten/sui/client';
import type { WalletInitializer } from '@mysten/dapp-kit-core';

export function testWalletInitializer(secretKey: string): WalletInitializer {
  return {
    id: 'test-wallet-initializer',
    async initialize({ networks, getClient }) {
      const wallet = new TestWallet({
        secretKey,
        clients: networks.map(getClient),
      });
      const unregister = getWallets().register(wallet);
      return { unregister };
    },
  };
}

class TestWallet implements Wallet {
  #chainConfig: Record<IdentifierString, ClientWithCoreApi>;
  #keypair: Ed25519Keypair;
  #account: ReadonlyWalletAccount;

  constructor({
    secretKey,
    clients,
  }: {
    secretKey: string;
    clients: ClientWithCoreApi[];
  }) {
    this.#keypair = Ed25519Keypair.fromSecretKey(secretKey);

    this.#chainConfig = clients.reduce<
      Record<IdentifierString, ClientWithCoreApi>
    >((acc, client) => {
      acc[`sui:${client.network}` as IdentifierString] = client;
      return acc;
    }, {});

    this.#account = new ReadonlyWalletAccount({
      address: this.#keypair.getPublicKey().toSuiAddress(),
      publicKey: this.#keypair.getPublicKey().toSuiBytes(),
      chains: this.chains,
      features: [
        SuiSignTransaction,
        SuiSignAndExecuteTransaction,
        SuiSignPersonalMessage,
      ],
    });
  }

  get version() {
    return '1.0.0' as const;
  }

  get name() {
    return 'Test Wallet' as const;
  }

  get icon() {
    return 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzIiIGhlaWdodD0iMzIiIHZpZXdCb3g9IjAgMCAzMiAzMiIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMzIiIGhlaWdodD0iMzIiIHJ4PSI0IiBmaWxsPSIjNjM2NkYxIi8+PHRleHQgeD0iMTYiIHk9IjIyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSJ3aGl0ZSIgZm9udC1zaXplPSIxOCI+VDwvdGV4dD48L3N2Zz4=' as const;
  }

  get chains() {
    return Object.keys(this.#chainConfig) as IdentifierArray;
  }

  get accounts() {
    return [this.#account];
  }

  get features(): StandardConnectFeature & StandardEventsFeature & SuiFeatures {
    return {
      [StandardConnect]: {
        version: '1.0.0',
        connect: this.#connect,
      },
      [StandardEvents]: {
        version: '1.0.0',
        on: this.#on,
      },
      [SuiSignPersonalMessage]: {
        version: '1.1.0',
        signPersonalMessage: this.#signPersonalMessage,
      },
      [SuiSignTransaction]: {
        version: '2.0.0',
        signTransaction: this.#signTransaction,
      },
      [SuiSignAndExecuteTransaction]: {
        version: '2.0.0',
        signAndExecuteTransaction: this.#signAndExecuteTransaction,
      },
    };
  }

  #on: StandardEventsOnMethod = () => {
    return () => {};
  };

  #connect: StandardConnectMethod = async () => {
    return { accounts: this.accounts };
  };

  #signPersonalMessage: SuiSignPersonalMessageMethod = async (messageInput) => {
    return await this.#keypair.signPersonalMessage(messageInput.message);
  };

  #signTransaction: SuiSignTransactionMethod = async ({
    transaction,
    signal,
    chain,
  }) => {
    signal?.throwIfAborted();

    const client = this.#chainConfig[chain];
    if (!client) throw new Error(`Invalid chain "${chain}" specified.`);

    const parsedTransaction = Transaction.from(await transaction.toJSON());
    const builtTransaction = await parsedTransaction.build({ client });
    return await this.#keypair.signTransaction(builtTransaction);
  };

  #signAndExecuteTransaction: SuiSignAndExecuteTransactionMethod = async ({
    transaction,
    signal,
    chain,
  }) => {
    signal?.throwIfAborted();

    const client = this.#chainConfig[chain];
    if (!client) throw new Error(`Invalid chain "${chain}" specified.`);

    const parsedTransaction = Transaction.from(await transaction.toJSON());
    const bytes = await parsedTransaction.build({ client });

    const result = await this.#keypair.signAndExecuteTransaction({
      transaction: parsedTransaction,
      client,
    });

    const tx = result.Transaction ?? result.FailedTransaction;
    return {
      bytes: toBase64(bytes),
      signature: tx.signatures[0],
      digest: tx.digest,
      effects: toBase64(tx.effects.bcs!),
    };
  };
}
