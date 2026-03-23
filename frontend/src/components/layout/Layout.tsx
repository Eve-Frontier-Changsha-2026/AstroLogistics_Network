import { Outlet } from 'react-router-dom';
import { Navbar } from './Navbar';

export function Layout() {
  return (
    <div className="min-h-screen flex flex-col">
      <Navbar />
      <main className="flex-1 p-6 max-w-7xl mx-auto w-full">
        <Outlet />
      </main>
    </div>
  );
}
