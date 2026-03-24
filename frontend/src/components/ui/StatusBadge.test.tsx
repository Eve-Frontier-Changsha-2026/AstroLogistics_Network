import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StatusBadge } from './StatusBadge';

describe('StatusBadge', () => {
  it.each([
    ['Open', 'bg-blue-900/60'],
    ['Accepted', 'bg-yellow-900/60'],
    ['Delivered', 'bg-green-900/60'],
    ['Disputed', 'bg-red-900/60'],
  ])('renders %s with correct color', (status, expectedClass) => {
    render(<StatusBadge status={status} />);
    const badge = screen.getByText(status);
    expect(badge).toBeInTheDocument();
    expect(badge.className).toContain(expectedClass);
  });

  it('uses fallback colors for unknown status', () => {
    render(<StatusBadge status="Unknown" />);
    expect(screen.getByText('Unknown').className).toContain('bg-gray-800');
  });
});
