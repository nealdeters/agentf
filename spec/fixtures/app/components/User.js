import React from 'react';

export function User({ name, email }) {
  return (
    <div className="user">
      <h2>{name}</h2>
      <p>{email}</p>
    </div>
  );
}
