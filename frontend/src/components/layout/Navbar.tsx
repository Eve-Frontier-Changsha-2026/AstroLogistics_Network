import { ConnectButton } from '@mysten/dapp-kit-react/ui';
import { NavLink } from 'react-router-dom';

const NAV_ITEMS = [
  { to: '/', label: 'Dashboard' },
  { to: '/bounty', label: 'Bounty Board' },
  { to: '/fuel', label: 'Fuel Station' },
  { to: '/transport', label: 'Transport' },
  { to: '/guild', label: 'Guild' },
  { to: '/threats', label: 'Threats' },
] as const;

export function Navbar() {
  return (
    <nav className="flex items-center justify-between px-6 py-3 border-b"
         style={{ borderColor: 'var(--color-border)', background: 'var(--color-bg-secondary)' }}>
      <div className="flex items-center gap-6">
        <span className="text-lg font-bold" style={{ fontFamily: 'var(--font-display)', color: 'var(--color-accent)' }}>
          AstroLogistics
        </span>
        <div className="flex gap-4">
          {NAV_ITEMS.map(({ to, label }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `text-sm transition-colors ${isActive ? 'text-cyan-400' : 'text-gray-400 hover:text-gray-200'}`
              }
            >
              {label}
            </NavLink>
          ))}
        </div>
      </div>
      <ConnectButton />
    </nav>
  );
}
