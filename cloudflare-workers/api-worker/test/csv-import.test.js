// test/csv-import.test.js
import { describe, test, expect, vi } from 'vitest';
import { handleCSVImport, processCSVImport } from '../src/handlers/csv-import.js';

describe('CSV Import Handler', () => {
  test('POST /api/import/csv-gemini returns jobId and token', async () => {
    const formData = new FormData();
    formData.append('file', new File(['Title,Author\nBook1,Author1'], 'test.csv'));

    const request = new Request('http://localhost/api/import/csv-gemini', {
      method: 'POST',
      body: formData
    });

    const mockDoStub = {
      scheduleCSVProcessing: vi.fn().mockResolvedValue(undefined),
      setAuthToken: vi.fn().mockResolvedValue(undefined),
    };

    const mockEnv = {
      PROGRESS_WEBSOCKET_DO: {
        idFromName: vi.fn(() => 'do-id'),
        get: vi.fn(() => mockDoStub),
      },
    };

    const response = await handleCSVImport(request, mockEnv);
    const body = await response.json();

    expect(response.status).toBe(202);
    expect(body.data).toBeDefined();
    expect(body.data.jobId).toBeDefined();
    expect(body.data.token).toBeDefined();
    expect(typeof body.data.token).toBe('string');
    expect(body.metadata).toBeDefined();
    expect(body.error).toBeUndefined();
    expect(mockDoStub.scheduleCSVProcessing).toHaveBeenCalled();
    expect(mockDoStub.setAuthToken).toHaveBeenCalled();
  });

  test('rejects files larger than 10MB', async () => {
    const largeContent = 'x'.repeat(11 * 1024 * 1024);
    const formData = new FormData();
    formData.append('file', new File([largeContent], 'large.csv'));

    const request = new Request('http://localhost/api/import/csv-gemini', {
      method: 'POST',
      body: formData
    });

    const response = await handleCSVImport(request, {});
    const body = await response.json();

    expect(response.status).toBe(413);
    expect(body.data).toBeNull();
    expect(body.error).toBeDefined();
    expect(body.error.message).toContain('too large');
    expect(body.error.code).toBe('E_FILE_TOO_LARGE');
    expect(body.metadata.timestamp).toBeDefined();
  });
});
