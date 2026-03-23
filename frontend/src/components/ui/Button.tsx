import type { ButtonHTMLAttributes } from 'react';

type Variant = 'primary' | 'secondary' | 'danger';

const VARIANT_CLASSES: Record<Variant, string> = {
  primary: 'bg-cyan-600 hover:bg-cyan-500 text-white',
  secondary: 'bg-gray-700 hover:bg-gray-600 text-gray-200 border border-gray-600',
  danger: 'bg-red-600 hover:bg-red-500 text-white',
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  loading?: boolean;
}

export function Button({ variant = 'primary', loading, disabled, children, className = '', ...props }: ButtonProps) {
  return (
    <button
      disabled={disabled || loading}
      className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${VARIANT_CLASSES[variant]} ${className}`}
      {...props}
    >
      {loading ? 'Processing...' : children}
    </button>
  );
}
