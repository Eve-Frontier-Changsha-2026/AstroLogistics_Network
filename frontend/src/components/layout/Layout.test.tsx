import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { Layout } from './Layout';

vi.mock('@mysten/dapp-kit-react', () => ({
  useDAppKit: vi.fn(() => ({})),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

describe('Layout', () => {
  it('renders Navbar and Outlet content', () => {
    render(
      <MemoryRouter initialEntries={['/']}>
        <Routes>
          <Route element={<Layout />}>
            <Route index element={<p>Home Page</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    );
    expect(screen.getByText('AstroLogistics')).toBeInTheDocument();
    expect(screen.getByText('Home Page')).toBeInTheDocument();
  });
});
