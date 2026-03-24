import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AddressDisplay } from './AddressDisplay';

describe('AddressDisplay', () => {
  const address = '0x' + 'a'.repeat(64);

  beforeEach(() => {
    Object.assign(navigator, { clipboard: { writeText: vi.fn().mockResolvedValue(undefined) } });
  });

  it('displays truncated address', () => {
    render(<AddressDisplay address={address} />);
    expect(screen.getByText('0xaaaa...aaaa')).toBeInTheDocument();
  });

  it('copies full address on click', async () => {
    render(<AddressDisplay address={address} />);
    await userEvent.click(screen.getByRole('button'));
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(address);
  });

  it('shows "Copied!" after click', async () => {
    render(<AddressDisplay address={address} />);
    await userEvent.click(screen.getByRole('button'));
    expect(screen.getByText('Copied!')).toBeInTheDocument();
  });
});
