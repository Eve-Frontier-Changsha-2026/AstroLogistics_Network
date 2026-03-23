import type { InputHTMLAttributes } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
}

export function Input({ label, id, className = '', ...props }: InputProps) {
  const inputId = id ?? label.toLowerCase().replace(/\s+/g, '-');
  return (
    <div className={className}>
      <label htmlFor={inputId} className="block text-xs text-gray-400 mb-1">{label}</label>
      <input
        id={inputId}
        className="w-full px-3 py-2 rounded-lg bg-gray-800 border border-gray-600 text-gray-100 text-sm focus:outline-none focus:border-cyan-500"
        {...props}
      />
    </div>
  );
}
