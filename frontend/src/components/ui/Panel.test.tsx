import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { Panel } from './Panel';

describe('Panel', () => {
  it('renders children', () => {
    render(<Panel>Content here</Panel>);
    expect(screen.getByText('Content here')).toBeInTheDocument();
  });

  it('renders title when provided', () => {
    render(<Panel title="My Title">Content</Panel>);
    expect(screen.getByText('My Title')).toBeInTheDocument();
  });

  it('does not render title element when not provided', () => {
    const { container } = render(<Panel>Content</Panel>);
    expect(container.querySelector('h3')).toBeNull();
  });
});
