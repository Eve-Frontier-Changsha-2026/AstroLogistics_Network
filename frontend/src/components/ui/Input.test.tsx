import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Input } from './Input';

describe('Input', () => {
  it('renders label', () => {
    render(<Input label="Amount" />);
    expect(screen.getByLabelText('Amount')).toBeInTheDocument();
  });

  it('generates id from label', () => {
    render(<Input label="Fuel Cost" />);
    expect(screen.getByLabelText('Fuel Cost')).toHaveAttribute('id', 'fuel-cost');
  });

  it('uses provided id over generated', () => {
    render(<Input label="Amount" id="custom-id" />);
    expect(screen.getByLabelText('Amount')).toHaveAttribute('id', 'custom-id');
  });

  it('handles value change', async () => {
    const onChange = vi.fn();
    render(<Input label="Val" value="" onChange={onChange} />);
    await userEvent.type(screen.getByLabelText('Val'), '42');
    expect(onChange).toHaveBeenCalled();
  });
});
