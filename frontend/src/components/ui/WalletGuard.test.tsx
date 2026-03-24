import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { WalletGuard } from './WalletGuard';
import { MOCK_ACCOUNT } from '../../test/mocks';

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useCurrentAccount } from '@mysten/dapp-kit-react';

describe('WalletGuard', () => {
  it('renders children when wallet is connected', () => {
    render(<WalletGuard><p>Protected content</p></WalletGuard>);
    expect(screen.getByText('Protected content')).toBeInTheDocument();
  });

  it('shows connect prompt when wallet is disconnected', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    render(<WalletGuard><p>Protected content</p></WalletGuard>);
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument();
    expect(screen.getByText('Connect your wallet to continue.')).toBeInTheDocument();
  });
});
