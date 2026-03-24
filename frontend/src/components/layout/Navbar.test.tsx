import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { Navbar } from './Navbar';

vi.mock('@mysten/dapp-kit-react', () => ({
  useDAppKit: vi.fn(() => ({})),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: ({ instance: _instance }: { instance: unknown }) => <button>Connect Wallet</button>,
}));

describe('Navbar', () => {
  const renderNavbar = () => render(
    <MemoryRouter><Navbar /></MemoryRouter>
  );

  it('renders brand name', () => {
    renderNavbar();
    expect(screen.getByText('AstroLogistics')).toBeInTheDocument();
  });

  it('renders all nav links', () => {
    renderNavbar();
    expect(screen.getByText('Dashboard')).toBeInTheDocument();
    expect(screen.getByText('Bounty Board')).toBeInTheDocument();
    expect(screen.getByText('Fuel Station')).toBeInTheDocument();
    expect(screen.getByText('Transport')).toBeInTheDocument();
    expect(screen.getByText('Guild')).toBeInTheDocument();
    expect(screen.getByText('Threats')).toBeInTheDocument();
  });

  it('renders ConnectButton', () => {
    renderNavbar();
    expect(screen.getByText('Connect Wallet')).toBeInTheDocument();
  });
});
