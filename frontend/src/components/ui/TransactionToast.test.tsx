import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, act } from '@testing-library/react';
import { TransactionToast } from './TransactionToast';

describe('TransactionToast', () => {
  const onClose = vi.fn();
  beforeEach(() => vi.clearAllMocks());

  it('is hidden when digest and error are null', () => {
    const { container } = render(<TransactionToast digest={null} error={null} onClose={onClose} />);
    expect(container.firstChild).toBeNull();
  });

  it('shows success message with explorer link when digest is set', async () => {
    render(<TransactionToast digest="tx-abc123" error={null} onClose={onClose} />);
    await waitFor(() => expect(screen.getByText('Success!')).toBeInTheDocument());
    const link = screen.getByRole('link', { name: 'View on explorer' });
    expect(link).toHaveAttribute('href', 'https://suiscan.xyz/testnet/tx/tx-abc123');
  });

  it('shows error message when error is set', async () => {
    render(<TransactionToast digest={null} error="Abort: 42" onClose={onClose} />);
    await waitFor(() => expect(screen.getByText(/Transaction failed: Abort: 42/)).toBeInTheDocument());
  });

  it('auto-closes after 5 seconds', async () => {
    vi.useFakeTimers();
    render(<TransactionToast digest="tx-123" error={null} onClose={onClose} />);
    // flush the useEffect that sets visible=true
    await act(async () => { vi.runAllTicks(); });
    expect(screen.getByText('Success!')).toBeInTheDocument();
    act(() => { vi.advanceTimersByTime(5000); });
    expect(onClose).toHaveBeenCalledOnce();
    vi.useRealTimers();
  }, 10000);
});
